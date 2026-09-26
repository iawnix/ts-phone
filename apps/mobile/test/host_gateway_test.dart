import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:ts_phone/data/host_gateway.dart';
import 'package:ts_phone/data/host_rpc_client.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _serverId = '123e4567-e89b-42d3-a456-426614174000';
final _settings = ConnectionSettings(
  serverUrl: 'https://link.example.test',
  serverId: _serverId,
  deviceId: '223e4567-e89b-42d3-a456-426614174000',
  token: 'tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

Map<String, Object?> _session({bool online = true, bool readOnly = false}) => {
  'workspace_id': 'ts_001',
  'session_id': 'session-1',
  'version': 3,
  'online': online,
  'read_only': readOnly,
  'is_streaming': false,
  'created_at': '2026-09-21T10:00:00Z',
  'name': 'A calculation',
};
Map<String, Object?> _snapshot({String text = 'first', bool online = true}) => {
  'messages': [
    {'role': 'user', 'content': text, 'timestamp': 1750000000000},
  ],
  'is_streaming': false,
  'turn_id': null,
  'online': online,
  'read_only': false,
  'can_prompt': online,
};
Map<String, Object?> _read({
  String epoch = 'epoch-a',
  int sequence = 10,
  String text = 'first',
  bool nestedCursor = false,
}) => {
  'session': _session(),
  'snapshot': _snapshot(text: text),
  if (!nestedCursor) 'epoch': epoch,
  if (!nestedCursor) 'sequence': sequence,
  if (nestedCursor) 'cursor': {'epoch': epoch, 'sequence': sequence},
};
Map<String, Object?> _event({
  String workspace = 'ts_001',
  String epoch = 'epoch-a',
  int sequence = 11,
  String text = 'updated',
}) => {
  'method': 'session/event',
  'params': {
    'workspace_id': workspace,
    'session_id': 'session-1',
    'epoch': epoch,
    'sequence': sequence,
    'type': 'snapshot',
    'snapshot': _snapshot(text: text),
  },
};

void main() {
  test(
    'uses Host JSON RPC and accepts split UTF-8 and coalesced NDJSON',
    () async {
      final server = _Server();
      final client = server.client();
      addTearDown(client.close);
      expect((await client.connect())['protocol'], tspiHostProtocol);
      expect(server.uri, Uri.parse('wss://link.example.test/v1/link'));
      expect(server.headers, {'Authorization': 'Bearer ${_settings.token}'});
      expect(server.requests.single['method'], 'initialize');
      expect(server.requests.single.containsKey('type'), isFalse);
      final events = StreamQueue(client.notifications);
      addTearDown(events.cancel);
      server.onRequest = (request) {
        final bytes = utf8.encode(
          '${jsonEncode({
            'id': request['id'],
            'result': {'text': '你好'},
          })}\n${jsonEncode(_event())}\n',
        );
        final multibyte = bytes.indexOf(0xe4);
        server.channel.add(Uint8List.fromList(bytes.sublist(0, multibyte + 1)));
        server.channel.add(Uint8List.fromList(bytes.sublist(multibyte + 1)));
      };
      expect(await client.request('session/read'), {'text': '你好'});
      expect((await events.next)['method'], 'session/event');
    },
  );

  test(
    'reconnects after a dropped request without retrying the mutation',
    () async {
      final server = _Server();
      final client = server.client();
      addTearDown(client.close);
      await client.connect();
      server.onRequest = (_) =>
          server.channel.addError(StateError('link dropped'));
      await expectLater(
        client.request('input/send', {'client_message_id': 'same-id'}),
        throwsStateError,
      );
      server.onRequest = (request) => server.respond(request, {'ok': true});
      expect(await client.request('session/list'), {'ok': true});
      expect(server.connections, 2);
      expect(
        server.requests.where((request) => request['method'] == 'input/send'),
        hasLength(1),
      );
      expect(
        server.requests.where((request) => request['method'] == 'initialize'),
        hasLength(2),
      );
    },
  );

  test(
    'projects persisted runtime failures into the session snapshot',
    () async {
      final server = _Server();
      final gateway = HostGateway(_settings, client: server.client());
      addTearDown(gateway.close);
      server.onRequest = (request) {
        expect(request['method'], 'session/read');
        server.respond(request, {
          ..._read(),
          'snapshot': {
            ..._snapshot(),
            'messages': <Object?>[
              {
                'role': 'assistant',
                'content': <Object?>[],
                'outputState': 'failed',
                'failure': {
                  'code': 'provider_error',
                  'summary': '模型服务拒绝了请求',
                  'detail': "400: Invalid 'tools[1].name'",
                  'statusCode': 400,
                  'retryable': false,
                  'operationId': 'run-1',
                },
              },
            ],
            'runtime_error': {
              'code': 'provider_error',
              'summary': '模型服务拒绝了请求',
              'detail': "400: Invalid 'tools[1].name'",
              'statusCode': 400,
              'retryable': false,
              'operationId': 'run-1',
            },
          },
        });
      };

      final snapshot = await gateway.getMessages('ts_001', 'session-1');
      final failure = (snapshot.messages.single! as Map)['failure'] as Map;
      expect((snapshot.messages.single! as Map)['outputState'], 'failed');
      expect(failure['code'], 'provider_error');
      expect(failure['statusCode'], 400);
      expect(failure['detail'], "400: Invalid 'tools[1].name'");
    },
  );

  test(
    'reconciles early events with attach snapshot and reattaches after a new epoch',
    () async {
      final server = _Server();
      final gateway = HostGateway(_settings, client: server.client());
      addTearDown(gateway.close);
      server.onRequest = (request) {
        expect(request['method'], 'session/attach');
        final params = request['params']! as Map;
        expect(params['after_cursor'], {'epoch': 'old', 'sequence': 999});
        server.send(_event(sequence: 11));
        server.respond(request, _read(nestedCursor: true));
      };
      final stream = StreamQueue(
        gateway.events('ts_001', 'session-1', lastEventId: 'old:999'),
      );
      expect((await stream.next).id, 'epoch-a:10');
      expect((await stream.next).id, 'epoch-a:11');
      server.send(_event(sequence: 11, text: 'duplicate'));
      server.send(_event(workspace: 'ts_002', sequence: 12));
      server.send(_event(sequence: 13, text: 'latest'));
      final latest = await stream.next;
      expect(latest.id, 'epoch-a:13');
      expect((latest.payload! as Map)['messages'][0]['content'], 'latest');
      await stream.cancel();
      server.channel.addError(StateError('link dropped'));
      server.onRequest = (request) => server.respond(
        request,
        _read(epoch: 'epoch-b', sequence: 1, text: 'after reconnect'),
      );
      final reconnected = StreamQueue(
        gateway.events('ts_001', 'session-1', lastEventId: latest.id),
      );
      final recovered = await reconnected.next;
      expect(recovered.id, 'epoch-b:1');
      expect(recovered.sessionRevision, latest.sessionRevision);
      expect(
        (recovered.payload! as Map)['messages'][0]['content'],
        'after reconnect',
      );
      expect(
        server.requests.where((value) => value['method'] == 'session/attach'),
        hasLength(2),
      );
      await reconnected.cancel();
    },
  );

  test(
    'retry keeps the outbox client_message_id after uncertain delivery',
    () async {
      final server = _Server();
      var sends = 0;
      server.onRequest = (request) {
        switch (request['method']) {
          case 'session/read' || 'session/attach':
            server.respond(request, {
              ..._read(),
              'snapshot': {..._snapshot(), 'messages': []},
            });
          case 'input/send':
            sends++;
            server.respond(request, {
              'accepted': true,
              'state': sends == 1 ? 'uncertain' : 'submitted',
              'duplicate': sends > 1,
            });
          default:
            fail('Unexpected ${request['method']}');
        }
      };
      final gateway = HostGateway(_settings, client: server.client());
      final initial = await gateway.getMessages('ts_001', 'session-1');
      var generated = 0;
      final controller = ChatController(
        api: gateway,
        workspaceId: 'ts_001',
        sessionId: 'session-1',
        initialSessionRevision: initial.sessionRevision,
        initialRuntimeState: RuntimeState.idle,
        accessMode: SessionAccessMode.controller,
        clientMessageIdFactory: () => 'outbox-${++generated}',
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(await controller.send('calculate'), isFalse);
      expect(
        controller.outbox.messages.single.state,
        ChatDeliveryState.uncertain,
      );
      expect(await controller.send('calculate'), isTrue);
      final inputs = server.requests
          .where((value) => value['method'] == 'input/send')
          .toList();
      expect(inputs, hasLength(2));
      expect((inputs[0]['params']! as Map)['client_message_id'], 'outbox-1');
      expect(inputs[1]['params'], inputs[0]['params']);
      expect(generated, 1);
    },
  );

  test(
    'maps receipts and preserves offline/read-only session boundaries',
    () async {
      final server = _Server();
      final gateway = HostGateway(_settings, client: server.client());
      addTearDown(gateway.close);
      server.onRequest = (request) {
        if (request['method'] == 'session/list') {
          expect((request['params']! as Map)['workspace_id'], 'ts_001');
          server.respond(request, {
            'sessions': [_session(online: false, readOnly: true)],
          });
        } else {
          server.respond(request, {
            ..._read(),
            'snapshot': {
              ..._snapshot(),
              'receipts': [
                {
                  'client_message_id': 'recovered-id',
                  'state': 'observed',
                  'message_index': 0,
                },
              ],
            },
          });
        }
      };
      final session = (await gateway.listSessions('ts_001')).single;
      expect(session.accessMode, SessionAccessMode.observer);
      expect(session.runtimeState, RuntimeState.offline);
      expect(session.canPrompt, isFalse);
      expect(session.historyOnly, isTrue);
      final snapshot = await gateway.getMessages('ts_001', 'session-1');
      expect(
        (snapshot.messages.single! as Map)['clientMessageId'],
        'recovered-id',
      );
    },
  );

  test('unwraps Pi Harness transcript message envelopes', () async {
    final server = _Server();
    final gateway = HostGateway(_settings, client: server.client());
    addTearDown(gateway.close);
    server.onRequest = (request) {
      expect(request['method'], 'session/read');
      server.respond(request, {
        ..._read(nestedCursor: true),
        'snapshot': {
          ..._snapshot(),
          'messages': [
            {
              'id': 'entry-1',
              'parentId': null,
              'type': 'message',
              'message': {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'from Harness'},
                ],
              },
              'seq': 4,
              'timestamp': 1750000000123,
            },
            {'role': 'assistant', 'content': 'flat message'},
          ],
          'receipts': [
            {
              'client_message_id': 'harness-user-id',
              'state': 'observed',
              'message_index': 0,
            },
          ],
        },
      });
    };

    final snapshot = await gateway.getMessages('ts_001', 'session-1');
    expect(snapshot.messages, hasLength(2));
    expect(snapshot.lastEventId, 'epoch-a:10');
    expect((snapshot.messages[0]! as Map)['role'], 'user');
    expect((snapshot.messages[0]! as Map)['content'], [
      {'type': 'text', 'text': 'from Harness'},
    ]);
    expect((snapshot.messages[0]! as Map)['timestamp'], 1750000000123);
    expect(
      (snapshot.messages[0]! as Map)['clientMessageId'],
      'harness-user-id',
    );
    expect((snapshot.messages[1]! as Map)['content'], 'flat message');
  });

  test('maps monitor management and structured Host failures', () async {
    final server = _Server();
    final gateway = HostGateway(_settings, client: server.client());
    addTearDown(gateway.close);
    server.onRequest = (request) {
      if (request['method'] == 'monitor/list') {
        server.respond(request, {
          'monitors': [
            {
              'monitor_id': 'm-1',
              'intent_id': 'calculation',
              'enabled': true,
              'state': {'last_state': 'running'},
              'delivery': {'pending_count': 2},
            },
          ],
        });
      } else {
        expect(request['method'], 'monitor/disable');
        expect((request['params']! as Map)['monitor_id'], 'm-1');
        server.send({
          'id': request['id'],
          'error': {
            'code': 'workspace_not_found',
            'message': 'Project is missing',
            'retryable': false,
          },
        });
      }
    };
    final monitor = (await gateway.listMonitors('ts_001')).single;
    expect(monitor.id, 'm-1');
    expect(monitor.pendingCount, 2);
    await expectLater(
      gateway.setMonitorEnabled('ts_001', 'm-1', false),
      throwsA(
        isA<TsPhoneApiException>().having(
          (error) => error.code,
          'code',
          'workspace_not_found',
        ),
      ),
    );
  });

  test('keeps cached workspaces while the relay reconnects', () async {
    final server = _Server();
    final gateway = HostGateway(_settings, client: server.client());
    addTearDown(gateway.close);
    var workspaceReads = 0;
    server.onRequest = (request) {
      switch (request['method']) {
        case 'workspace/list':
          workspaceReads += 1;
          if (workspaceReads == 1) {
            server.respond(request, {
              'workspaces': [
                {'workspace_id': 'ts_001', 'name': 'Chemistry'},
              ],
            });
          } else {
            server.channel.addError(StateError('relay dropped'));
          }
        case 'session/list':
          server.respond(request, {
            'sessions': [_session()],
          });
        default:
          fail('Unexpected ${request['method']}');
      }
    };

    expect((await gateway.listWorkspaces()).single.name, 'Chemistry');
    expect(gateway.transportState, HostTransportState.connected);
    final states = <HostTransportState>[];
    final stateSubscription = gateway.transportChanges.listen(states.add);
    addTearDown(stateSubscription.cancel);

    final cached = await gateway.listWorkspaces();
    expect(cached.single.name, 'Chemistry');
    expect(gateway.transportState, HostTransportState.reconnecting);
    expect(states, contains(HostTransportState.reconnecting));
  });
}

class _Server {
  final requests = <Map<String, Object?>>[];
  late _Channel channel;
  void Function(Map<String, Object?>)? onRequest;
  Uri? uri;
  Map<String, dynamic>? headers;
  int connections = 0;

  HostRpcClient client() => HostRpcClient(
    gateway: Uri.parse(_settings.serverUrl),
    serverId: _serverId,
    token: _settings.token,
    channelFactory: (uri, headers) {
      this.uri = uri;
      this.headers = headers;
      connections++;
      channel = _Channel((value) {
        final text = utf8.decode(value! as List<int>);
        expect(text.endsWith('\n'), isTrue);
        final request = Map<String, Object?>.from(jsonDecode(text) as Map);
        requests.add(request);
        if (request['method'] == 'initialize') {
          respond(request, {
            'protocol': tspiHostProtocol,
            'server_id': _serverId,
            'epoch': 'epoch-a',
            'capabilities': [],
          });
        } else if (request['method'] == 'session/detach') {
          respond(request, {'accepted': true});
        } else {
          onRequest?.call(request);
        }
      });
      return channel;
    },
  );

  void respond(Map<String, Object?> request, Object? result) =>
      send({'id': request['id'], 'result': result});
  void send(Map<String, Object?> message) =>
      channel.add(Uint8List.fromList(utf8.encode('${jsonEncode(message)}\n')));
}

class _Channel with StreamChannelMixin<Object?> implements WebSocketChannel {
  _Channel(void Function(Object?) send) {
    outgoing.stream.listen(send);
    sink = _Sink(outgoing);
  }
  final incoming = StreamController<Object?>.broadcast(sync: true);
  final outgoing = StreamController<Object?>(sync: true);
  void add(Object? value) => incoming.add(value);
  void addError(Object error) => incoming.addError(error);
  @override
  Stream<Object?> get stream => incoming.stream;
  @override
  late final WebSocketSink sink;
  @override
  Future<void> get ready => Future.value();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => tspiHostLinkProtocol;
}

class _Sink extends DelegatingStreamSink<Object?> implements WebSocketSink {
  _Sink(super.sink);
  @override
  Future<void> close([int? closeCode, String? closeReason]) => super.close();
}
