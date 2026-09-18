import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:cbor/simple.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:ts_phone/data/app_server_gateway.dart';
import 'package:ts_phone/data/pi_app_server_client.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _serverId = '123e4567-e89b-42d3-a456-426614174000';

void main() {
  test('connects to Radius with the Pi relay protocol and v8 hello', () async {
    final server = _FakeRadiusServer();
    final client = server.client();
    addTearDown(client.close);

    final outgoing = server.nextMessage();
    final connecting = client.connect();
    expect(await outgoing, {'type': 'hello', 'version': 8});
    expect(
      server.uri,
      Uri.parse('wss://radius.pi.dev/v1/session-relays/$_serverId/connect'),
    );
    expect(server.headers, {
      'Authorization': 'Bearer abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
    });

    server.send({
      'type': 'hello',
      'version': 8,
      'serverId': _serverId,
      'services': const [],
    });
    await connecting;
  });

  test('decodes split and coalesced response and attachment frames', () async {
    final server = _FakeRadiusServer();
    final client = server.client();
    addTearDown(client.close);
    await server.connect(client);

    final outgoing = server.nextMessage();
    final attaching = client.attach('session-1');
    final request = await outgoing;
    expect(request['type'], 'request');
    expect(request['target'], {'serverId': _serverId});
    expect(request['call'], {
      'serviceId': 'pi.session-management',
      'member': 'attach',
      'args': ['session-1'],
    });

    final requestId = request['id']! as String;
    final bytes = _joinFrames([
      {'type': 'response', 'id': requestId, 'ok': true, 'result': null},
      {
        'type': 'attachment',
        'attachment': {
          'serverId': _serverId,
          'sessionId': 'session-1',
          'attachmentId': 'attachment-1',
        },
      },
    ]);
    server.addBytes(Uint8List.sublistView(bytes, 0, 3));
    server.addBytes(Uint8List.sublistView(bytes, 3, 11));
    server.addBytes(Uint8List.sublistView(bytes, 11));
    await attaching;

    expect(client.sessionTarget, {
      'serverId': _serverId,
      'sessionId': 'session-1',
      'attachmentId': 'attachment-1',
    });
  });

  test(
    'creates a workspace through the Host workspace directory service',
    () async {
      final server = _FakeRadiusServer();
      final client = server.client();
      final gateway = PiAppServerGateway(_settings, client: client);
      addTearDown(gateway.close);
      await server.connect(client);

      final creating = gateway.createWorkspace('project-c');
      final request = await server.nextMessage();
      expect(request['call'], {
        'serviceId': 'tspi.workspace-directory',
        'member': 'create',
        'args': ['project-c'],
      });
      server.respond(request, {
        'workspaceId': 'project-c',
        'name': 'project-c',
        'root': '/srv/tspi/workspaces/project-c',
      });
      expect((await creating).id, 'project-c');
    },
  );

  test(
    'hydrates Chord state after an early update and applies path ids',
    () async {
      final server = _FakeRadiusServer();
      final client = server.client();
      addTearDown(client.close);
      await server.connect(client);
      await server.attach(client, 'session-1');

      final outgoing = server.nextMessage();
      final opening = client.subscribe(client.sessionTarget, 'pi.transcript');
      final request = await outgoing;
      final subscriptionId = (request['call']! as Map)['args'][0] as String;
      expect((request['call']! as Map)['args'], [
        subscriptionId,
        'pi.transcript',
        'singleton',
      ]);

      server.send({
        'type': 'service_update',
        'subscriptionId': subscriptionId,
        'update': {
          'type': 'state',
          'member': 'state',
          'sequence': 1,
          'ops': [
            [
              '#',
              0,
              ['revision'],
            ],
            ['s', 0, 1],
          ],
        },
      });
      server.respond(request, {
        'serviceId': 'pi.transcript',
        'mode': 'singleton',
        'instances': [
          {
            'members': [
              {
                'name': 'state',
                'kind': 'state',
                'sequence': 0,
                'ops': [
                  [
                    'r',
                    {'revision': 0, 'snapshot': null},
                  ],
                ],
              },
            ],
          },
        ],
      });
      final state = await opening;
      expect(state.value, {'revision': 1, 'snapshot': null});

      final changed = state.updates.first;
      server.send({
        'type': 'service_update',
        'subscriptionId': subscriptionId,
        'update': {
          'type': 'state',
          'member': 'state',
          'sequence': 2,
          'ops': [
            ['s', 0, 2],
          ],
        },
      });
      expect(await changed, {'revision': 2, 'snapshot': null});

      final unsubscribe = server.nextMessage();
      final closing = state.close();
      final closeRequest = await unsubscribe;
      expect((closeRequest['call']! as Map)['member'], 'unsubscribe');
      server.respond(closeRequest, null);
      await closing;
    },
  );

  test('opens a new transport after a connection failure', () async {
    final server = _FakeRadiusServer();
    final client = server.client();
    addTearDown(client.close);
    await server.connect(client);
    expect(server.connectionCount, 1);

    server.fail(StateError('network lost'));
    await Future<void>.delayed(Duration.zero);

    final outgoing = server.nextMessage();
    final reconnecting = client.connect();
    expect(await outgoing, {'type': 'hello', 'version': 8});
    expect(server.connectionCount, 2);
    server.send({
      'type': 'hello',
      'version': 8,
      'serverId': _serverId,
      'services': const [],
    });
    await reconnecting;
  });

  test('uses the native session directory and management services', () async {
    final server = _FakeRadiusServer();
    final client = server.client();
    final gateway = PiAppServerGateway(_settings, client: client);
    addTearDown(gateway.close);
    await server.connect(client);

    final listing = gateway.listSessions(appServerWorkspaceId);
    final subscribe = await server.nextMessage();
    expect((subscribe['call']! as Map)['args'], [
      isA<String>(),
      'pi.session-directory',
      'singleton',
    ]);
    server.respond(
      subscribe,
      _serviceSnapshot('pi.session-directory', {
        'revision': 3,
        'sessions': [
          {
            'serverId': _serverId,
            'sessionId': 'session-existing',
            'createdAt': 1700000000000,
          },
        ],
      }),
    );
    final unsubscribe = await server.nextMessage();
    server.respond(unsubscribe, null);
    final sessions = await listing;
    expect(sessions.single.sessionId, 'session-existing');

    final creating = gateway.createSession();
    final create = await server.nextMessage();
    expect(create['call'], {
      'serviceId': 'pi.session-management',
      'member': 'create',
      'args': [<String, Object?>{}],
    });
    server.respond(create, {
      'serverId': _serverId,
      'sessionId': 'session-new',
      'createdAt': 1700000001000,
    });
    expect((await creating).sessionId, 'session-new');

    final removing = gateway.removeSession('session-new');
    final remove = await server.nextMessage();
    expect(remove['call'], {
      'serviceId': 'pi.session-management',
      'member': 'remove',
      'args': ['session-new'],
    });
    server.respond(remove, null);
    await removing;
  });

  test('lists Host workspaces and creates a session in the selected workspace', () async {
    final server = _FakeRadiusServer();
    final client = server.client();
    final gateway = PiAppServerGateway(_settings, client: client);
    addTearDown(gateway.close);
    await server.connect(client);

    final listing = gateway.listWorkspaces();
    final workspaceRequest = await server.nextMessage();
    expect(workspaceRequest['call'], {
      'serviceId': 'tspi.workspace-directory',
      'member': 'list',
      'args': const [],
    });
    server.respond(workspaceRequest, [
      {
        'workspaceId': 'project-a',
        'name': 'project-a',
        'root': '/srv/tspi/workspaces/project-a',
      },
      {
        'workspaceId': 'project-b',
        'name': 'project-b',
        'root': '/srv/tspi/workspaces/project-b',
      },
    ]);
    final subscribe = await server.nextMessage();
    server.respond(
      subscribe,
      _serviceSnapshot('pi.session-directory', {
        'revision': 4,
        'sessions': [
          {
            'serverId': _serverId,
            'sessionId': 'session-a',
            'createdAt': 1700000000000,
            'cwd': '/srv/tspi/workspaces/project-a',
          },
        ],
      }),
    );
    final unsubscribe = await server.nextMessage();
    server.respond(unsubscribe, null);
    final workspaces = await listing;
    expect(workspaces.map((workspace) => workspace.id), ['project-a', 'project-b']);
    expect(workspaces.first.sessionCount, 1);

    final creating = gateway.createWorkspaceSession('project-b');
    final create = await server.nextMessage();
    expect(create['call'], {
      'serviceId': 'pi.session-management',
      'member': 'create',
      'args': [
        {'workspaceId': 'project-b'},
      ],
    });
    server.respond(create, {
      'serverId': _serverId,
      'sessionId': 'session-b',
      'createdAt': 1700000001000,
      'cwd': '/srv/tspi/workspaces/project-b',
    });
    expect((await creating).sessionId, 'session-b');
  });

  test(
    'projects transcripts and sends native prompt and followUp calls',
    () async {
      final server = _FakeRadiusServer();
      final client = server.client();
      final gateway = PiAppServerGateway(_settings, client: client);
      addTearDown(gateway.close);
      await server.connect(client);

      final loading = gateway.getMessages(appServerWorkspaceId, 'session-1');
      final attach = await server.nextMessage();
      server.respond(attach, null);
      server.send({
        'type': 'attachment',
        'attachment': {
          'serverId': _serverId,
          'sessionId': 'session-1',
          'attachmentId': 'attachment-1',
        },
      });
      final subscribe = await server.nextMessage();
      server.respond(
        subscribe,
        _serviceSnapshot('pi.transcript', {
          'snapshot': {
            'operation': null,
            'transcript': [
              {
                'id': 'entry-1',
                'type': 'message',
                'message': {'role': 'user', 'content': 'inspect the pathway'},
              },
            ],
          },
          'event': null,
        }),
      );
      final unsubscribe = await server.nextMessage();
      server.respond(unsubscribe, null);
      final transcript = await loading;
      expect(transcript.messageIds, ['entry-1']);
      expect(transcript.messages.single, {
        'role': 'user',
        'content': 'inspect the pathway',
      });

      final prompting = gateway.sendMessage(
        appServerWorkspaceId,
        'session-1',
        transcript.sessionRevision,
        'continue',
        clientMessageId: 'phone-message-1',
      );
      final prompt = await server.nextMessage();
      expect((prompt['call']! as Map)['member'], 'prompt');
      expect((prompt['call']! as Map)['args'], [
        {'message': 'continue', 'images': null},
      ]);
      server.respond(prompt, {
        'accepted': true,
        'operationId': 'operation-1',
        'error': null,
      });
      await prompting;
    },
  );
}

final _settings = ConnectionSettings(
  serverUrl: 'https://radius.pi.dev',
  serverId: _serverId,
  token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

Map<String, Object?> _serviceSnapshot(
  String serviceId,
  Map<String, Object?> value,
) => {
  'serviceId': serviceId,
  'mode': 'singleton',
  'instances': [
    {
      'members': [
        {
          'name': 'state',
          'kind': 'state',
          'sequence': 0,
          'ops': [
            ['r', value],
          ],
        },
      ],
    },
  ],
};

class _FakeRadiusServer {
  _FakeWebSocketChannel? _channel;
  final _outgoing = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  Uri? uri;
  Map<String, dynamic>? headers;
  int connectionCount = 0;

  PiAppServerClient client() => PiAppServerClient(
    gateway: Uri.parse('https://radius.pi.dev'),
    serverId: _serverId,
    token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
    channelFactory: (uri, headers) {
      this.uri = uri;
      this.headers = Map<String, dynamic>.from(headers);
      connectionCount += 1;
      final channel = _FakeWebSocketChannel(
        onSend: (value) => _outgoing.add(_decodeFrame(value)),
      );
      _channel = channel;
      return channel;
    },
  );

  Future<Map<String, Object?>> nextMessage() => _outgoing.stream.first;

  Future<void> connect(PiAppServerClient client) async {
    final outgoing = nextMessage();
    final connecting = client.connect();
    expect(await outgoing, {'type': 'hello', 'version': 8});
    send({
      'type': 'hello',
      'version': 8,
      'serverId': _serverId,
      'services': const [],
    });
    await connecting;
  }

  Future<void> attach(PiAppServerClient client, String sessionId) async {
    final outgoing = nextMessage();
    final attaching = client.attach(sessionId);
    final request = await outgoing;
    respond(request, null);
    send({
      'type': 'attachment',
      'attachment': {
        'serverId': _serverId,
        'sessionId': sessionId,
        'attachmentId': 'attachment-1',
      },
    });
    await attaching;
  }

  void respond(Map<String, Object?> request, Object? result) {
    send({
      'type': 'response',
      'id': request['id'],
      'ok': true,
      'result': result,
    });
  }

  void send(Map<String, Object?> message) => addBytes(_encodeFrame(message));

  void addBytes(Uint8List bytes) => _channel!.add(bytes);

  void fail(Object error) => _channel!.addError(error);
}

class _FakeWebSocketChannel
    with StreamChannelMixin<Object?>
    implements WebSocketChannel {
  _FakeWebSocketChannel({required void Function(Object?) onSend})
    : _incoming = StreamController<Object?>.broadcast(sync: true),
      _sinkController = StreamController<Object?>(sync: true) {
    _sinkController.stream.listen(onSend);
    _sink = _FakeWebSocketSink(_sinkController);
  }

  final StreamController<Object?> _incoming;
  final StreamController<Object?> _sinkController;
  late final WebSocketSink _sink;

  void add(Object? value) => _incoming.add(value);
  void addError(Object error) => _incoming.addError(error);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => piRadiusClientProtocol;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<Object?> get stream => _incoming.stream;
}

class _FakeWebSocketSink extends DelegatingStreamSink<Object?>
    implements WebSocketSink {
  _FakeWebSocketSink(super.sink);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await super.close();
  }
}

Uint8List _encodeFrame(Map<String, Object?> message) {
  final payload = Uint8List.fromList(const CborSimpleCodec().encode(message));
  final frame = ByteData(payload.length + 4)
    ..setUint32(0, payload.length, Endian.big);
  frame.buffer.asUint8List().setRange(4, payload.length + 4, payload);
  return frame.buffer.asUint8List();
}

Uint8List _joinFrames(List<Map<String, Object?>> messages) {
  final frames = messages.map(_encodeFrame).toList(growable: false);
  final result = Uint8List(
    frames.fold(0, (length, frame) => length + frame.length),
  );
  var offset = 0;
  for (final frame in frames) {
    result.setRange(offset, offset + frame.length, frame);
    offset += frame.length;
  }
  return result;
}

Map<String, Object?> _decodeFrame(Object? value) {
  final bytes = value! as Uint8List;
  final length = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
  expect(bytes.length, length + 4);
  final decoded = const CborSimpleCodec().decode(
    Uint8List.sublistView(bytes, 4),
    parseDateTime: false,
    parseUri: false,
  );
  return Map<String, Object?>.from(decoded! as Map);
}
