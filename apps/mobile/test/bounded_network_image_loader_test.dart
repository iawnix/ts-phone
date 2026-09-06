import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ts_phone/data/bounded_network_image_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads valid HTTPS image within byte and decode limits', () async {
    final progress = <BoundedImageDownloadProgress>[];
    final loader = BoundedNetworkImageLoader(
      clientFactory: () => MockClient(
        (request) async => MockClient.pngResponse(request: request),
      ),
    );

    final image = await loader.load(
      Uri.parse('https://example.test/plot.png'),
      onProgress: progress.add,
    );

    expect(image.sourceWidth, 1);
    expect(image.sourceHeight, 1);
    expect(image.decodeWidth, 1);
    expect(image.decodeHeight, 1);
    expect(image.bytes, isNotEmpty);
    expect(progress.first.downloadedBytes, 0);
    expect(progress.last.downloadedBytes, image.bytes.length);
    expect(progress.last.fraction, 1);
  });

  test('rejects a declared body larger than the download limit', () async {
    final loader = BoundedNetworkImageLoader(
      maxDownloadBytes: 8,
      clientFactory: () => MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(
          const http.ByteStream(Stream<List<int>>.empty()),
          200,
          contentLength: 9,
        ),
      ),
    );

    await expectLater(
      loader.load(Uri.parse('https://example.test/plot.png')),
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'download_too_large',
        ),
      ),
    );
  });

  test('rejects chunked data once it crosses the download limit', () async {
    final loader = BoundedNetworkImageLoader(
      maxDownloadBytes: 8,
      clientFactory: () => MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(
          http.ByteStream(
            Stream<List<int>>.fromIterable(const <List<int>>[
              <int>[0, 1, 2, 3, 4],
              <int>[5, 6, 7, 8],
            ]),
          ),
          200,
        ),
      ),
    );

    await expectLater(
      loader.load(Uri.parse('https://example.test/plot.png')),
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'download_too_large',
        ),
      ),
    );
  });

  test('rejects non-HTTPS image requests before creating a client', () async {
    var clientCreated = false;
    final loader = BoundedNetworkImageLoader(
      clientFactory: () {
        clientCreated = true;
        return MockClient((request) async => http.Response('', 200));
      },
    );

    await expectLater(
      loader.load(Uri.parse('http://example.test/plot.png')),
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'invalid_uri',
        ),
      ),
    );
    expect(clientCreated, isFalse);
  });

  test('follows only explicitly validated HTTPS redirects', () async {
    final requestedUris = <Uri>[];
    final redirectBody = StreamController<List<int>>.broadcast();
    addTearDown(redirectBody.close);
    final loader = BoundedNetworkImageLoader(
      clientFactory: () => MockClient.streaming((request, bodyStream) async {
        requestedUris.add(request.url);
        expect(request.followRedirects, isFalse);
        if (request.url.path == '/start') {
          return http.StreamedResponse(
            http.ByteStream(redirectBody.stream),
            302,
            headers: <String, String>{'location': '/plot.png'},
          );
        }
        return _pngStreamedResponse(request);
      }),
    );

    final image = await loader.load(Uri.parse('https://example.test/start'));

    expect(image.bytes, isNotEmpty);
    expect(requestedUris, <Uri>[
      Uri.parse('https://example.test/start'),
      Uri.parse('https://example.test/plot.png'),
    ]);
  });

  test('rejects an HTTPS redirect that downgrades to HTTP', () async {
    var requestCount = 0;
    final loader = BoundedNetworkImageLoader(
      clientFactory: () => MockClient.streaming((request, bodyStream) async {
        requestCount += 1;
        return http.StreamedResponse(
          const http.ByteStream(Stream<List<int>>.empty()),
          302,
          headers: <String, String>{'location': 'http://example.test/plot.png'},
        );
      }),
    );

    await expectLater(
      loader.load(Uri.parse('https://example.test/start')),
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'unsafe_redirect',
        ),
      ),
    );
    expect(requestCount, 1);
  });

  test('enforces one redirect limit across the complete request', () async {
    var requestCount = 0;
    final loader = BoundedNetworkImageLoader(
      maxRedirects: 1,
      clientFactory: () => MockClient.streaming((request, bodyStream) async {
        requestCount += 1;
        return http.StreamedResponse(
          const http.ByteStream(Stream<List<int>>.empty()),
          302,
          headers: <String, String>{'location': '/next$requestCount'},
        );
      }),
    );

    await expectLater(
      loader.load(Uri.parse('https://example.test/start')),
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'too_many_redirects',
        ),
      ),
    );
    expect(requestCount, 2);
  });

  test('times out while waiting for response headers', () async {
    final pendingResponse = Completer<http.StreamedResponse>();
    final loader = BoundedNetworkImageLoader(
      networkTimeout: const Duration(milliseconds: 30),
      clientFactory: () =>
          MockClient.streaming((request, bodyStream) => pendingResponse.future),
    );

    await expectLater(
      loader.load(Uri.parse('https://example.test/plot.png')),
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'network_timeout',
        ),
      ),
    );
  });

  test('times out while a response body remains open', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final loader = BoundedNetworkImageLoader(
      networkTimeout: const Duration(milliseconds: 30),
      clientFactory: () => MockClient.streaming(
        (request, bodyStream) async =>
            http.StreamedResponse(http.ByteStream(body.stream), 200),
      ),
    );

    final load = loader.load(Uri.parse('https://example.test/plot.png'));
    body.add(const <int>[137, 80, 78, 71]);

    await expectLater(
      load,
      throwsA(
        isA<BoundedImageLoadException>().having(
          (error) => error.code,
          'code',
          'network_timeout',
        ),
      ),
    );
  });

  test(
    'decode size preserves aspect ratio within dimension and pixel caps',
    () {
      final landscape = constrainImageDecodeSize(
        sourceWidth: 12000,
        sourceHeight: 3000,
        maxDimension: 4096,
        maxPixels: 8 * 1024 * 1024,
      );
      expect(landscape.width, 4096);
      expect(landscape.height, 1024);

      final square = constrainImageDecodeSize(
        sourceWidth: 8000,
        sourceHeight: 8000,
        maxDimension: 4096,
        maxPixels: 8 * 1024 * 1024,
      );
      expect(square.width, lessThanOrEqualTo(4096));
      expect(square.height, lessThanOrEqualTo(4096));
      expect(square.width * square.height, lessThanOrEqualTo(8 * 1024 * 1024));
    },
  );

  test('download progress clamps inconsistent server totals', () {
    const beyondTotal = BoundedImageDownloadProgress(
      downloadedBytes: 12,
      expectedBytes: 10,
    );
    const unknownTotal = BoundedImageDownloadProgress(
      downloadedBytes: 12,
      expectedBytes: 0,
    );

    expect(beyondTotal.fraction, 1);
    expect(unknownTotal.fraction, isNull);
  });
}

http.StreamedResponse _pngStreamedResponse(http.BaseRequest request) {
  final response = MockClient.pngResponse(request: request);
  return http.StreamedResponse(
    Stream<List<int>>.value(response.bodyBytes),
    response.statusCode,
    headers: response.headers,
    request: request,
  );
}
