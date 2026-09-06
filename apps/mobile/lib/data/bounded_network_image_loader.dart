import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

const int maxMarkdownImageDownloadBytes = 8 * 1024 * 1024;
const int maxMarkdownImageSourceDimension = 16384;
const int maxMarkdownImageSourcePixels = 64 * 1024 * 1024;
const int maxMarkdownImageDecodeDimension = 4096;
const int maxMarkdownImageDecodePixels = 8 * 1024 * 1024;
const int maxMarkdownImageRedirects = 5;
const Duration markdownImageNetworkTimeout = Duration(seconds: 30);

typedef ImageDownloadProgressCallback =
    void Function(BoundedImageDownloadProgress progress);

class BoundedImageDownloadProgress {
  const BoundedImageDownloadProgress({
    required this.downloadedBytes,
    required this.expectedBytes,
  });

  final int downloadedBytes;
  final int? expectedBytes;

  double? get fraction {
    final total = expectedBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

class BoundedImageData {
  const BoundedImageData({
    required this.bytes,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.decodeWidth,
    required this.decodeHeight,
  });

  final Uint8List bytes;
  final int sourceWidth;
  final int sourceHeight;
  final int decodeWidth;
  final int decodeHeight;
}

class BoundedImageLoadException implements Exception {
  const BoundedImageLoadException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BoundedImageLoadException($code): $message';
}

class BoundedNetworkImageLoader {
  const BoundedNetworkImageLoader({
    this.clientFactory,
    this.maxDownloadBytes = maxMarkdownImageDownloadBytes,
    this.maxSourceDimension = maxMarkdownImageSourceDimension,
    this.maxSourcePixels = maxMarkdownImageSourcePixels,
    this.maxDecodeDimension = maxMarkdownImageDecodeDimension,
    this.maxDecodePixels = maxMarkdownImageDecodePixels,
    this.maxRedirects = maxMarkdownImageRedirects,
    this.networkTimeout = markdownImageNetworkTimeout,
  }) : assert(maxDownloadBytes > 0),
       assert(maxSourceDimension > 0),
       assert(maxSourcePixels > 0),
       assert(maxDecodeDimension > 0),
       assert(maxDecodePixels > 0),
       assert(maxRedirects >= 0);

  final http.Client Function()? clientFactory;
  final int maxDownloadBytes;
  final int maxSourceDimension;
  final int maxSourcePixels;
  final int maxDecodeDimension;
  final int maxDecodePixels;
  final int maxRedirects;
  final Duration networkTimeout;

  Future<BoundedImageData> load(
    Uri uri, {
    ImageDownloadProgressCallback? onProgress,
    Future<void>? abortTrigger,
  }) async {
    if (networkTimeout <= Duration.zero) {
      throw ArgumentError.value(
        networkTimeout,
        'networkTimeout',
        'must be positive',
      );
    }
    _validateHttpsUri(uri, code: 'invalid_uri');
    final cancellation = _NetworkCancellation(
      timeout: networkTimeout,
      externalTrigger: abortTrigger,
    );
    try {
      final data = await _download(
        uri,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      if (data.isEmpty) {
        throw const BoundedImageLoadException(
          'invalid_image',
          'Image response was empty.',
        );
      }
      return _inspect(data);
    } finally {
      cancellation.dispose();
    }
  }

  Future<Uint8List> _download(
    Uri initialUri, {
    required _NetworkCancellation cancellation,
    ImageDownloadProgressCallback? onProgress,
  }) async {
    var currentUri = initialUri;
    var redirectCount = 0;
    while (true) {
      final client = clientFactory?.call() ?? http.Client();
      try {
        final request =
            http.AbortableRequest(
                'GET',
                currentUri,
                abortTrigger: cancellation.signal,
              )
              ..headers['Accept'] = 'image/*'
              ..followRedirects = false;
        final response = await cancellation.guard(
          client.send(request),
          uri: currentUri,
        );
        if (_isRedirect(response.statusCode)) {
          if (redirectCount >= maxRedirects) {
            throw BoundedImageLoadException(
              'too_many_redirects',
              'Image request exceeded the $maxRedirects redirect limit.',
            );
          }
          final location = response.headers['location'];
          if (location == null || location.trim().isEmpty) {
            throw const BoundedImageLoadException(
              'invalid_redirect',
              'Image redirect did not include a Location header.',
            );
          }
          late final Uri nextUri;
          try {
            nextUri = currentUri.resolve(location);
          } on FormatException {
            throw const BoundedImageLoadException(
              'invalid_redirect',
              'Image redirect included an invalid Location value.',
            );
          }
          _validateHttpsUri(nextUri, code: 'unsafe_redirect');
          currentUri = nextUri;
          redirectCount += 1;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw BoundedImageLoadException(
            'http_status',
            'Image request returned HTTP ${response.statusCode}.',
          );
        }
        return await _readBody(
          response,
          uri: currentUri,
          cancellation: cancellation,
          onProgress: onProgress,
        );
      } finally {
        client.close();
      }
    }
  }

  Future<Uint8List> _readBody(
    http.StreamedResponse response, {
    required Uri uri,
    required _NetworkCancellation cancellation,
    ImageDownloadProgressCallback? onProgress,
  }) async {
    final expectedBytes = response.contentLength;
    if (expectedBytes != null && expectedBytes > maxDownloadBytes) {
      throw BoundedImageLoadException(
        'download_too_large',
        'Image declares $expectedBytes bytes; limit is $maxDownloadBytes.',
      );
    }

    final bytes = BytesBuilder(copy: false);
    var downloadedBytes = 0;
    onProgress?.call(
      BoundedImageDownloadProgress(
        downloadedBytes: 0,
        expectedBytes: expectedBytes,
      ),
    );
    final chunks = StreamIterator<List<int>>(response.stream);
    try {
      while (await cancellation.guard(chunks.moveNext(), uri: uri)) {
        final chunk = chunks.current;
        if (chunk.length > maxDownloadBytes - downloadedBytes) {
          throw BoundedImageLoadException(
            'download_too_large',
            'Image exceeded the $maxDownloadBytes byte download limit.',
          );
        }
        bytes.add(chunk);
        downloadedBytes += chunk.length;
        onProgress?.call(
          BoundedImageDownloadProgress(
            downloadedBytes: downloadedBytes,
            expectedBytes: expectedBytes,
          ),
        );
      }
    } finally {
      await chunks.cancel();
    }
    return bytes.takeBytes();
  }

  Future<BoundedImageData> _inspect(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw const BoundedImageLoadException(
          'invalid_dimensions',
          'Image dimensions must be positive.',
        );
      }
      if (sourceWidth > maxSourceDimension ||
          sourceHeight > maxSourceDimension ||
          sourceWidth * sourceHeight > maxSourcePixels) {
        throw BoundedImageLoadException(
          'source_dimensions_too_large',
          'Image source dimensions ${sourceWidth}x$sourceHeight exceed the limit.',
        );
      }

      final decodeSize = constrainImageDecodeSize(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        maxDimension: maxDecodeDimension,
        maxPixels: maxDecodePixels,
      );
      return BoundedImageData(
        bytes: bytes,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        decodeWidth: decodeSize.width,
        decodeHeight: decodeSize.height,
      );
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

bool _isRedirect(int statusCode) => switch (statusCode) {
  301 || 302 || 303 || 307 || 308 => true,
  _ => false,
};

void _validateHttpsUri(Uri uri, {required String code}) {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw BoundedImageLoadException(
      code,
      'Remote image URI must use HTTPS, include a host, and omit credentials.',
    );
  }
}

class _NetworkCancellation {
  _NetworkCancellation({
    required Duration timeout,
    required Future<void>? externalTrigger,
  }) {
    _timer = Timer(timeout, () {
      _timedOut = true;
      if (!_signal.isCompleted) _signal.complete();
    });
    if (externalTrigger != null) {
      unawaited(
        externalTrigger.then((_) {
          if (!_signal.isCompleted) _signal.complete();
        }),
      );
    }
  }

  final Completer<void> _signal = Completer<void>();
  late final Timer _timer;
  bool _timedOut = false;

  Future<void> get signal => _signal.future;

  Future<T> guard<T>(Future<T> operation, {required Uri uri}) {
    return Future.any<T>(<Future<T>>[
      operation,
      signal.then<T>((_) {
        if (_timedOut) {
          throw const BoundedImageLoadException(
            'network_timeout',
            'Image request exceeded the network time limit.',
          );
        }
        throw http.RequestAbortedException(uri);
      }),
    ]);
  }

  void dispose() => _timer.cancel();
}

class BoundedImageDecodeSize {
  const BoundedImageDecodeSize({required this.width, required this.height});

  final int width;
  final int height;
}

BoundedImageDecodeSize constrainImageDecodeSize({
  required int sourceWidth,
  required int sourceHeight,
  required int maxDimension,
  required int maxPixels,
}) {
  if (sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      maxDimension <= 0 ||
      maxPixels <= 0) {
    throw ArgumentError('Image dimensions and limits must be positive.');
  }

  final longestSide = math.max(sourceWidth, sourceHeight);
  final sourcePixels = sourceWidth * sourceHeight;
  final dimensionScale = maxDimension / longestSide;
  final pixelScale = math.sqrt(maxPixels / sourcePixels);
  final scale = math.min(1.0, math.min(dimensionScale, pixelScale));
  final width = math.max(1, (sourceWidth * scale).floor());
  final height = math.max(1, (sourceHeight * scale).floor());
  return BoundedImageDecodeSize(width: width, height: height);
}
