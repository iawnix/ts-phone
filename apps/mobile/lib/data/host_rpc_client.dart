import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const tspiHostProtocol = 'tspi-host/1';
const tspiHostLinkProtocol = 'tspi-link.v1';
const _maxLineBytes = 16 * 1024 * 1024;

class HostRpcException implements Exception {
  const HostRpcException(this.message, {this.code, this.retryable = false});

  final String message;
  final String? code;
  final bool retryable;

  @override
  String toString() => message;
}

/// The relay carries UTF-8 NDJSON without knowing Pi's internal wire format.
/// Reconnection establishes a new connection; callers reattach for a snapshot.
/// Mutating requests are never automatically retried here.
class HostRpcClient {
  HostRpcClient({
    required this.gateway,
    required this.serverId,
    required this.token,
    this.requestTimeout = const Duration(seconds: 45),
    WebSocketChannel Function(Uri uri, Map<String, dynamic> headers)?
    channelFactory,
  }) : _channelFactory = channelFactory ?? _defaultChannelFactory;

  final Uri gateway;
  final String serverId;
  final String token;
  final Duration requestTimeout;
  final WebSocketChannel Function(Uri, Map<String, dynamic>) _channelFactory;
  final _pending = <String, Completer<Object?>>{};
  final _notifications = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _incoming;
  Future<Map<String, Object?>>? _connecting;
  Map<String, Object?>? _metadata;
  Uint8List _buffer = Uint8List(0);
  int _generation = 0;
  int _requestSequence = 0;
  bool _closed = false;

  Stream<Map<String, Object?>> get notifications => _notifications.stream;
  Map<String, Object?>? get metadata => _metadata;

  Future<Map<String, Object?>> connect() {
    if (_closed) {
      return Future.error(
        const HostRpcException(
          'Host connection is closed',
          code: 'connection_closed',
        ),
      );
    }
    return _connecting ??= _open(++_generation);
  }

  Future<Map<String, Object?>> _open(int generation) async {
    // Publish _connecting before a synchronous channel factory can fail.
    await Future<void>.value();
    try {
      final scheme = switch (gateway.scheme) {
        'https' => 'wss',
        'http' => 'ws',
        _ => throw const FormatException('Relay must use HTTP or HTTPS'),
      };
      final uri = gateway.replace(
        scheme: scheme,
        path: '/v1/link',
        query: null,
        fragment: null,
      );
      final channel = _channelFactory(uri, {'Authorization': 'Bearer $token'});
      _channel = channel;
      _buffer = Uint8List(0);
      _incoming = channel.stream.listen(
        (value) => _onChunk(generation, value),
        onError: (Object error) => _fail(generation, error),
        onDone: () => _fail(
          generation,
          const HostRpcException(
            'Host connection closed',
            code: 'connection_closed',
            retryable: true,
          ),
        ),
        cancelOnError: true,
      );
      await channel.ready.timeout(const Duration(seconds: 20));
      if (_closed || generation != _generation) {
        throw const HostRpcException(
          'Host connection closed',
          code: 'connection_closed',
        );
      }
      final response = await _request('initialize', {
        'protocol': tspiHostProtocol,
        'server_id': serverId,
        'client': {'name': 'ts-phone'},
      });
      if (response is! Map || response['protocol'] != tspiHostProtocol) {
        throw const HostRpcException(
          'Unsupported Host protocol',
          code: 'version',
        );
      }
      if (response['server_id'] != null && response['server_id'] != serverId) {
        throw const HostRpcException(
          'Host identity does not match the paired server',
          code: 'version',
        );
      }
      _metadata = Map<String, Object?>.from(response);
      return _metadata!;
    } on Object catch (error) {
      _fail(generation, error);
      rethrow;
    }
  }

  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    await connect();
    return _request(method, params);
  }

  Future<Object?> _request(String method, Map<String, Object?> params) async {
    final channel = _channel;
    if (channel == null || _closed) {
      throw const HostRpcException(
        'Host connection closed',
        code: 'connection_closed',
        retryable: true,
      );
    }
    final id = 'phone-${++_requestSequence}';
    final pending = Completer<Object?>();
    _pending[id] = pending;
    try {
      final data = utf8.encode(
        '${jsonEncode({'id': id, 'method': method, 'params': params})}\n',
      );
      if (data.length > _maxLineBytes) {
        throw const HostRpcException(
          'Host request is too large',
          code: 'invalid_request',
        );
      }
      channel.sink.add(Uint8List.fromList(data));
      return await pending.future.timeout(requestTimeout);
    } on TimeoutException {
      throw const HostRpcException(
        'Host request timed out; delivery may be uncertain',
        code: 'request_timeout',
        retryable: true,
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _onChunk(int generation, Object? value) {
    if (_closed || generation != _generation) return;
    try {
      final bytes = switch (value) {
        String text => utf8.encode(text),
        List<int> bytes => bytes,
        _ => throw const FormatException('Host returned an invalid frame'),
      };
      final combined = Uint8List(_buffer.length + bytes.length)
        ..setRange(0, _buffer.length, _buffer)
        ..setRange(_buffer.length, _buffer.length + bytes.length, bytes);
      var start = 0;
      for (var index = 0; index < combined.length; index++) {
        if (index - start >= _maxLineBytes) {
          throw const FormatException('Host message exceeds 16 MiB');
        }
        if (combined[index] != 10) continue;
        if (index > start) {
          final decoded = jsonDecode(
            utf8.decode(combined.sublist(start, index)),
          );
          if (decoded is! Map) {
            throw const FormatException('Invalid Host message');
          }
          _onMessage(Map<String, Object?>.from(decoded));
        }
        start = index + 1;
      }
      _buffer = Uint8List.fromList(combined.sublist(start));
    } on Object catch (error) {
      _fail(generation, error);
    }
  }

  void _onMessage(Map<String, Object?> message) {
    final id = message['id'];
    if (id is String) {
      final pending = _pending[id];
      if (pending == null || pending.isCompleted) return;
      final error = message['error'];
      if (error is Map) {
        pending.completeError(
          HostRpcException(
            error['message'] as String? ?? 'Host rejected the request',
            code: error['code']?.toString(),
            retryable: error['retryable'] == true,
          ),
        );
      } else if (message.containsKey('result')) {
        pending.complete(message['result']);
      } else {
        throw const FormatException('Host response has no result or error');
      }
    } else if (message['method'] is String && message['params'] is Map) {
      _notifications.add(message);
    } else {
      throw const FormatException('Invalid Host notification');
    }
  }

  void _fail(int generation, Object error) {
    if (_closed || generation != _generation) return;
    _generation++;
    _metadata = null;
    _connecting = null;
    final incoming = _incoming;
    final channel = _channel;
    _incoming = null;
    _channel = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
    if (_notifications.hasListener) _notifications.addError(error);
    unawaited(incoming?.cancel());
    unawaited(channel?.sink.close());
  }

  Future<void> close() async {
    if (_closed) return;
    _fail(
      _generation,
      const HostRpcException(
        'Host connection closed',
        code: 'connection_closed',
      ),
    );
    _closed = true;
    await _notifications.close();
  }

  static WebSocketChannel _defaultChannelFactory(
    Uri uri,
    Map<String, dynamic> headers,
  ) => IOWebSocketChannel.connect(
    uri,
    headers: headers,
    protocols: const [tspiHostLinkProtocol],
    pingInterval: const Duration(seconds: 20),
    connectTimeout: const Duration(seconds: 20),
  );
}
