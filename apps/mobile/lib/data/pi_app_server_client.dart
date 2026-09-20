import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const piAppServerProtocolVersion = 8;
const tspiLinkProtocol = 'tspi-link.v1';
const _maxFrameLength = 16 * 1024 * 1024;

class PiAppServerException implements Exception {
  const PiAppServerException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class PiServiceState {
  PiServiceState(this._read, this.updates, this._close);

  final Object? Function() _read;
  final Stream<Object?> updates;
  final Future<void> Function() _close;

  Object? get value => _read();

  Future<void> close() => _close();
}

class PiAppServerClient {
  PiAppServerClient({
    required this.gateway,
    required this.serverId,
    required this.token,
    WebSocketChannel Function(Uri uri, Map<String, dynamic> headers)?
    channelFactory,
  }) : _channelFactory = channelFactory ?? _defaultChannelFactory;

  final Uri gateway;
  final String serverId;
  final String token;
  final WebSocketChannel Function(Uri uri, Map<String, dynamic> headers)
  _channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _incoming;
  _FrameDecoder _frames = _FrameDecoder();
  final _pending = <String, Completer<Object?>>{};
  final _subscriptions = <String, _ServiceSubscription>{};
  final _attachmentChanges = StreamController<Map<String, Object?>?>.broadcast(
    sync: true,
  );
  Completer<void>? _hello;
  Map<String, Object?>? _attachment;
  Object? _terminalError;
  int _requestSequence = 0;
  int _subscriptionSequence = 0;
  int _connectionGeneration = 0;
  bool _closed = false;

  Map<String, Object?> get serverTarget => {'serverId': serverId};

  Map<String, Object?> get sessionTarget {
    final target = _attachment;
    if (target == null) {
      throw const PiAppServerException('No App Server session is attached');
    }
    return target;
  }

  Stream<Map<String, Object?>?> get attachmentChanges =>
      _attachmentChanges.stream;

  Future<void> connect() async {
    if (_closed) {
      throw const PiAppServerException('App Server client is closed');
    }
    if (_hello != null) return _hello!.future;
    _terminalError = null;
    _frames = _FrameDecoder();
    final generation = ++_connectionGeneration;
    final hello = Completer<void>();
    _hello = hello;
    final channel = _channelFactory(_linkUri(), {
      'Authorization': 'Bearer $token',
    });
    _channel = channel;
    _incoming = channel.stream.listen(
      (value) => _onChunk(generation, value),
      onError: (Object error) => _fail(generation, error),
      onDone: () => _fail(
        generation,
        const PiAppServerException('TSPi Link connection closed'),
      ),
      cancelOnError: true,
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 20));
      _send({'type': 'hello', 'version': piAppServerProtocolVersion});
      await hello.future.timeout(const Duration(seconds: 20));
    } on Object catch (error) {
      _fail(generation, error);
      rethrow;
    }
  }

  Future<Object?> request(
    Map<String, Object?> target,
    String serviceId,
    String member,
    List<Object?> args,
  ) async {
    await connect();
    final id = 'phone-${++_requestSequence}';
    final response = Completer<Object?>();
    _pending[id] = response;
    try {
      _send({
        'type': 'request',
        'id': id,
        'target': target,
        'call': {'serviceId': serviceId, 'member': member, 'args': args},
      });
      return await response.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      _send({'type': 'cancel', 'id': id, 'target': target});
      throw const PiAppServerException(
        'App Server request timed out',
        code: 'request_timeout',
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> attach(String sessionId) async {
    await connect();
    if (_attachment?['sessionId'] == sessionId) return;
    final attached = Completer<void>();
    late final StreamSubscription<Map<String, Object?>?> subscription;
    subscription = attachmentChanges.listen((value) {
      if (!attached.isCompleted && value?['sessionId'] == sessionId) {
        attached.complete();
      }
    });
    try {
      await request(serverTarget, 'pi.session-management', 'attach', [
        sessionId,
      ]);
      await attached.future.timeout(const Duration(seconds: 20));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> detach() async {
    if (_attachment == null) return;
    await request(serverTarget, 'pi.session-management', 'detach', const []);
  }

  Future<PiServiceState> subscribe(
    Map<String, Object?> target,
    String serviceId,
  ) async {
    final id = 'phone-service-${++_subscriptionSequence}';
    final controller = StreamController<Object?>.broadcast(sync: true);
    final subscription = _ServiceSubscription(id, serviceId, controller);
    _subscriptions[id] = subscription;
    try {
      final result = await request(target, r'$chord.service', 'subscribe', [
        id,
        serviceId,
        'singleton',
      ]);
      subscription.hydrate(result);
      return PiServiceState(
        () => subscription.value,
        controller.stream,
        () => _unsubscribe(target, subscription),
      );
    } on Object {
      _subscriptions.remove(id);
      await controller.close();
      rethrow;
    }
  }

  Future<void> _unsubscribe(
    Map<String, Object?> target,
    _ServiceSubscription subscription,
  ) async {
    if (_subscriptions.remove(subscription.id) == null) return;
    try {
      if (!_closed) {
        await request(target, r'$chord.service', 'unsubscribe', [
          subscription.id,
        ]);
      }
    } finally {
      await subscription.controller.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final subscriptions = _subscriptions.values.toList();
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.controller.close();
    }
    final incoming = _incoming;
    final channel = _channel;
    _incoming = null;
    _channel = null;
    _hello = null;
    _connectionGeneration += 1;
    await incoming?.cancel();
    await channel?.sink.close(1000, 'TS Phone disconnected');
    await _attachmentChanges.close();
    _rejectPending(const PiAppServerException('App Server client is closed'));
  }

  Uri _linkUri() {
    final scheme = switch (gateway.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => throw const PiAppServerException('TSPi Relay must use HTTPS'),
    };
    return gateway.replace(
      scheme: scheme,
      path: '/v1/link',
      query: null,
      fragment: null,
    );
  }

  void _send(Map<String, Object?> message) {
    final payload = Uint8List.fromList(const CborSimpleCodec().encode(message));
    if (payload.length > _maxFrameLength) {
      throw const PiAppServerException('App Server frame is too large');
    }
    final frame = ByteData(4 + payload.length);
    frame.setUint32(0, payload.length, Endian.big);
    frame.buffer.asUint8List().setRange(4, 4 + payload.length, payload);
    _channel!.sink.add(frame.buffer.asUint8List());
  }

  void _onChunk(int generation, Object? value) {
    if (generation != _connectionGeneration || _closed) return;
    try {
      final bytes = switch (value) {
        Uint8List bytes => bytes,
        List<int> bytes => Uint8List.fromList(bytes),
        _ => throw const PiAppServerException(
          'TSPi Link returned a non-binary App Server frame',
        ),
      };
      for (final frame in _frames.add(bytes)) {
        final decoded = const CborSimpleCodec().decode(
          frame,
          parseDateTime: false,
          parseUri: false,
        );
        _onMessage(_jsonObject(decoded, 'App Server message'));
      }
    } on Object catch (error) {
      _fail(generation, error);
    }
  }

  void _onMessage(Map<String, Object?> message) {
    switch (message['type']) {
      case 'hello':
        if (message['version'] != piAppServerProtocolVersion ||
            message['serverId'] != serverId) {
          throw const PiAppServerException(
            'App Server protocol identity mismatch',
            code: 'version',
          );
        }
        final hello = _hello;
        if (hello == null || hello.isCompleted) {
          throw const PiAppServerException('Unexpected App Server hello');
        }
        hello.complete();
      case 'hello_error':
        final error = _jsonObject(message['error'], 'hello error');
        _completeHelloError(error);
      case 'response':
        final id = message['id'];
        if (id is! String) {
          throw const PiAppServerException('Invalid App Server response');
        }
        final pending = _pending[id];
        if (pending == null || pending.isCompleted) return;
        if (message['ok'] == true) {
          pending.complete(_json(message['result']));
        } else {
          final error = _jsonObject(message['error'], 'response error');
          pending.completeError(
            PiAppServerException(
              error['message'] as String? ?? 'App Server request failed',
              code: error['code'] as String?,
            ),
          );
        }
      case 'attachment':
        final value = message['attachment'];
        _attachment = value == null
            ? null
            : _validateAttachment(_jsonObject(value, 'session attachment'));
        _attachmentChanges.add(_attachment);
      case 'service_update':
        final id = message['subscriptionId'];
        if (id is! String) {
          throw const PiAppServerException('Invalid service update');
        }
        _subscriptions[id]?.update(message['update']);
      default:
        throw const PiAppServerException('Unknown App Server message');
    }
  }

  void _completeHelloError(Map<String, Object?> error) {
    final exception = PiAppServerException(
      error['message'] as String? ?? 'App Server rejected the connection',
      code: error['code'] as String?,
    );
    final hello = _hello;
    if (hello != null && !hello.isCompleted) hello.completeError(exception);
  }

  Map<String, Object?> _validateAttachment(Map<String, Object?> attachment) {
    final server = attachment['serverId'];
    final session = attachment['sessionId'];
    final identity = attachment['attachmentId'];
    if (server != serverId ||
        session is! String ||
        session.isEmpty ||
        identity is! String ||
        identity.isEmpty) {
      throw const PiAppServerException(
        'Session attachment identity is invalid',
        code: 'attachment_identity',
      );
    }
    return attachment;
  }

  void _fail(int generation, Object error) {
    if (generation != _connectionGeneration ||
        _terminalError != null ||
        _closed) {
      return;
    }
    _terminalError = error;
    final exception = error is PiAppServerException
        ? error
        : PiAppServerException(error.toString());
    final hello = _hello;
    if (hello != null && !hello.isCompleted) hello.completeError(exception);
    _hello = null;
    _rejectPending(exception);
    final subscriptions = _subscriptions.values.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      subscription.controller.addError(exception);
      unawaited(subscription.controller.close());
    }
    if (_attachment != null) {
      _attachment = null;
      _attachmentChanges.add(null);
    }
    final incoming = _incoming;
    final channel = _channel;
    _incoming = null;
    _channel = null;
    unawaited(incoming?.cancel() ?? Future<void>.value());
    unawaited(
      channel?.sink.close(1011, 'App Server connection failed') ??
          Future<void>.value(),
    );
  }

  void _rejectPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  static WebSocketChannel _defaultChannelFactory(
    Uri uri,
    Map<String, dynamic> headers,
  ) => IOWebSocketChannel.connect(
    uri,
    protocols: const [tspiLinkProtocol],
    headers: headers,
    pingInterval: const Duration(seconds: 20),
    connectTimeout: const Duration(seconds: 20),
  );
}

class _ServiceSubscription {
  _ServiceSubscription(this.id, this.serviceId, this.controller);

  final String id;
  final String serviceId;
  final StreamController<Object?> controller;
  final _DeltaDecoder decoder = _DeltaDecoder();
  final List<Object?> _pendingUpdates = [];
  Object? value;
  int? sequence;
  bool _hydrated = false;

  void hydrate(Object? raw) {
    final snapshot = _jsonObject(raw, 'service snapshot');
    if (snapshot['serviceId'] != serviceId || snapshot['mode'] != 'singleton') {
      throw const PiAppServerException('Service snapshot identity mismatch');
    }
    final instances = snapshot['instances'];
    if (instances is! List || instances.length != 1) {
      throw const PiAppServerException('Singleton service is unavailable');
    }
    _hydrateInstance(_jsonObject(instances.single, 'service instance'));
    _hydrated = true;
    final pending = List<Object?>.of(_pendingUpdates);
    _pendingUpdates.clear();
    for (final update in pending) {
      _applyUpdate(update, publish: false);
    }
  }

  void update(Object? raw) {
    if (!_hydrated) {
      _pendingUpdates.add(raw);
      return;
    }
    _applyUpdate(raw, publish: true);
  }

  void _applyUpdate(Object? raw, {required bool publish}) {
    final update = _jsonObject(raw, 'service update');
    switch (update['type']) {
      case 'state':
        if (update['member'] != 'state' || update['sequence'] is! int) return;
        final nextSequence = update['sequence']! as int;
        if (sequence == null || nextSequence != sequence! + 1) {
          throw const PiAppServerException('Service state sequence has a gap');
        }
        value = _applyDelta(value, decoder.decode(update['ops']));
        sequence = nextSequence;
        if (publish) controller.add(value);
      case 'replaced':
        decoder.reset();
        _hydrateInstance(_jsonObject(update['snapshot'], 'service instance'));
        if (publish) controller.add(value);
      case 'unavailable':
        decoder.reset();
        value = null;
        sequence = null;
        if (publish) controller.add(null);
      case 'spawned':
      case 'closed':
        // Keyed-instance lifecycle updates are not part of a singleton
        // subscription. They may still arrive when a provider publishes a
        // shared catalogue update; the singleton replica remains unchanged.
        return;
      default:
        throw const PiAppServerException('Unknown service update');
    }
  }

  void _hydrateInstance(Map<String, Object?> instance) {
    final members = instance['members'];
    if (members is! List) {
      throw const PiAppServerException('Service members are invalid');
    }
    final state = members
        .map((value) => _jsonObject(value, 'service member'))
        .where((value) => value['kind'] == 'state' && value['name'] == 'state')
        .firstOrNull;
    if (state == null || state['sequence'] is! int) {
      throw const PiAppServerException('Service has no replicated state');
    }
    decoder.reset();
    value = _applyDelta(null, decoder.decode(state['ops']));
    sequence = state['sequence']! as int;
  }
}

class _DeltaDecoder {
  final _paths = <int, List<Object?>>{};

  void reset() => _paths.clear();

  List<List<Object?>> decode(Object? raw) {
    if (raw is! List) {
      throw const PiAppServerException('Service delta is invalid');
    }
    List<Object?>? previous;
    final decoded = <List<Object?>>[];
    for (final candidate in raw) {
      if (candidate is! List ||
          candidate.isEmpty ||
          candidate.first is! String) {
        throw const PiAppServerException('Service delta operation is invalid');
      }
      final operation = candidate.cast<Object?>();
      final verb = operation.first! as String;
      if (verb == '#') {
        if (operation.length != 3 || operation[1] is! int) {
          throw const PiAppServerException(
            'Service path definition is invalid',
          );
        }
        _paths[operation[1]! as int] = _path(operation[2]);
        continue;
      }
      if (verb == 'r') {
        if (operation.length != 2) {
          throw const PiAppServerException('Service replacement is invalid');
        }
        decoded.add(['r', _json(operation[1])]);
        _paths.clear();
        previous = null;
        continue;
      }
      final short =
          (verb == 'd' && operation.length == 1) ||
          (verb != 'd' && verb != 'p' && operation.length == 2) ||
          (verb == 'p' && operation.length == 4);
      final path = short ? previous : _resolvePath(operation[1]);
      if (path == null || (verb != 'p' && path.isEmpty)) {
        throw const PiAppServerException('Service delta path is invalid');
      }
      if (!short) previous = path;
      switch (verb) {
        case 's':
        case 'a':
        case 't':
          decoded.add([verb, path, _json(operation[short ? 1 : 2])]);
        case 'd':
          decoded.add([verb, path]);
        case 'p':
          decoded.add([
            verb,
            path,
            operation[short ? 1 : 2],
            operation[short ? 2 : 3],
            _json(operation[short ? 3 : 4]),
          ]);
        default:
          throw const PiAppServerException('Unknown service delta operation');
      }
    }
    return decoded;
  }

  List<Object?> _resolvePath(Object? ref) {
    if (ref is int) {
      final path = _paths[ref];
      if (path == null) {
        throw const PiAppServerException('Unknown service delta path');
      }
      return path;
    }
    return _path(ref);
  }

  static List<Object?> _path(Object? value) {
    if (value is! List ||
        value.any((segment) => segment is! String && segment is! int)) {
      throw const PiAppServerException('Service delta path is invalid');
    }
    return value.cast<Object?>();
  }
}

Object? _applyDelta(Object? root, List<List<Object?>> operations) {
  for (final operation in operations) {
    final verb = operation[0]! as String;
    if (verb == 'r') {
      root = _json(operation[1]);
      continue;
    }
    final path = operation[1]! as List<Object?>;
    if (verb == 'p') {
      final target = path.isEmpty ? root : _resolve(root, path);
      if (target is! List) {
        throw const PiAppServerException('Service splice target is invalid');
      }
      final index = operation[2];
      final remove = operation[3];
      final items = operation[4];
      if (index is! int || remove is! int || items is! List) {
        throw const PiAppServerException('Service splice is invalid');
      }
      if (index < 0 ||
          remove < 0 ||
          index > target.length ||
          remove > target.length - index) {
        throw const PiAppServerException('Service splice range is invalid');
      }
      target.replaceRange(index, index + remove, items);
      continue;
    }
    final parent = _resolve(root, path.sublist(0, path.length - 1));
    final key = path.last;
    switch (verb) {
      case 's':
        _write(parent, key, operation[2]);
      case 'd':
        _delete(parent, key);
      case 'a':
        final current = _read(parent, key);
        if (current is! String || operation[2] is! String) {
          throw const PiAppServerException('Service string append is invalid');
        }
        _write(parent, key, current + (operation[2]! as String));
      case 't':
        final current = _read(parent, key);
        final count = operation[2];
        if (current is! String || count is! int) {
          throw const PiAppServerException(
            'Service string truncate is invalid',
          );
        }
        _write(parent, key, current.substring(count));
    }
  }
  return root;
}

Object? _resolve(Object? root, List<Object?> path) {
  var current = root;
  for (final segment in path) {
    current = _read(current, segment);
  }
  return current;
}

Object? _read(Object? parent, Object? key) {
  if (parent is List && key is int && key >= 0 && key < parent.length) {
    return parent[key];
  }
  if (parent is Map<String, Object?> &&
      key is String &&
      parent.containsKey(key)) {
    return parent[key];
  }
  throw const PiAppServerException('Service delta references a missing path');
}

void _write(Object? parent, Object? key, Object? value) {
  if (parent is List && key is int && key >= 0 && key <= parent.length) {
    if (key == parent.length) {
      parent.add(value);
    } else {
      parent[key] = value;
    }
    return;
  }
  if (parent is Map<String, Object?> && key is String) {
    parent[key] = value;
    return;
  }
  throw const PiAppServerException('Service delta write path is invalid');
}

void _delete(Object? parent, Object? key) {
  if (parent is List && key is int && key >= 0 && key < parent.length) {
    parent.removeAt(key);
    return;
  }
  if (parent is Map<String, Object?> && key is String) {
    parent.remove(key);
    return;
  }
  throw const PiAppServerException('Service delta delete path is invalid');
}

Object? _json(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const PiAppServerException('CBOR object key is not a string');
      }
      result[entry.key! as String] = _json(entry.value);
    }
    return result;
  }
  if (value is List) return value.map(_json).toList();
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const PiAppServerException('CBOR value is not strict JSON');
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  final normalized = _json(value);
  if (normalized is! Map<String, Object?>) {
    throw PiAppServerException('$label must be an object');
  }
  return normalized;
}

class _FrameDecoder {
  Uint8List _buffer = Uint8List(0);

  List<Uint8List> add(Uint8List chunk) {
    final combined = Uint8List(_buffer.length + chunk.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
    _buffer = combined;
    final frames = <Uint8List>[];
    var offset = 0;
    while (_buffer.length - offset >= 4) {
      final length = ByteData.sublistView(
        _buffer,
        offset,
        offset + 4,
      ).getUint32(0, Endian.big);
      if (length > _maxFrameLength) {
        throw const PiAppServerException('App Server frame exceeds 16 MiB');
      }
      if (_buffer.length - offset - 4 < length) break;
      frames.add(
        Uint8List.sublistView(_buffer, offset + 4, offset + 4 + length),
      );
      offset += 4 + length;
    }
    _buffer = Uint8List.fromList(_buffer.sublist(offset));
    return frames;
  }
}
