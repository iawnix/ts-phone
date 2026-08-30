import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/models/workspace.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
  final settings = ConnectionSettings(
    serverUrl: 'https://phone.test',
    token: token,
  );

  test('parses workspace envelopes and sends Bearer authentication', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer $token');
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode(<String, Object?>{
            'apiVersion': 'ts-phone-api/3',
            'data': <Object?>[
              <String, Object?>{
                'id': 'ts_001',
                'name': 'ts_001',
                'runtimeState': 'idle',
                'isStreaming': false,
                'liveSessionCount': 1,
                'sessionCount': 1,
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final workspaces = await api.listWorkspaces();
    expect(workspaces.single.id, 'ts_001');
    expect(workspaces.single.runtimeState, RuntimeState.idle);
  });

  test('parses SSE envelopes and sends Last-Event-ID', () async {
    var connected = false;
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        expect(request.headers['Last-Event-ID'], 'epoch:3');
        final event = <String, Object?>{
          'protocolVersion': 'ts-phone-events/3',
          'id': 'epoch:4',
          'workspaceId': 'ts_001',
          'sessionId': 'session-test',
          'sessionRevision': '11111111-1111-4111-8111-111111111111',
          'instanceEpoch': 'instance-1',
          'sessionGeneration': 1,
          'type': 'session_state',
          'payload': <String, Object?>{'state': 'idle'},
          'at': '2026-08-14T12:00:00.000Z',
        };
        return http.Response(
          'id: epoch:4\nevent: session_state\ndata: ${jsonEncode(event)}\n\n',
          200,
        );
      }),
    );
    addTearDown(api.close);

    final event = await api
        .events(
          'ts_001',
          'session-test',
          lastEventId: 'epoch:3',
          onConnected: () => connected = true,
        )
        .first;
    expect(connected, isTrue);
    expect(event.id, 'epoch:4');
    expect(event.type, 'session_state');
    expect(event.instanceEpoch, 'instance-1');
  });

  test('parses the message checkpoint cursor', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'apiVersion': 'ts-phone-api/3',
            'data': <String, Object?>{
              'sessionId': 'session-test',
              'sessionRevision': '11111111-1111-4111-8111-111111111111',
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'content': 'hello'},
              ],
              'lastEventId': 'epoch:12',
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final snapshot = await api.getMessages('ts_001', 'session-test');
    expect(snapshot.messages, hasLength(1));
    expect(snapshot.lastEventId, 'epoch:12');
    expect(snapshot.messageIds, isNull);
    expect(snapshot.hasMore, isFalse);
  });

  test('requests and parses an earlier message page', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        expect(request.url.queryParameters, <String, String>{
          'before': '0000000a',
          'limit': '200',
        });
        return http.Response(
          jsonEncode(<String, Object?>{
            'apiVersion': 'ts-phone-api/3',
            'data': <String, Object?>{
              'sessionId': 'session-test',
              'sessionRevision': '11111111-1111-4111-8111-111111111111',
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'content': 'earlier'},
              ],
              'messageIds': <String>['00000009'],
              'hasMore': true,
              'nextBefore': '00000009',
              'lastEventId': 'epoch:12',
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final page = await api.getMessages(
      'ts_001',
      'session-test',
      before: '0000000a',
      limit: 200,
    );
    expect(page.messageIds, <String>['00000009']);
    expect(page.hasMore, isTrue);
    expect(page.nextBefore, '00000009');
  });

  test('parses optional disk-history session capabilities', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(<String, Object?>{
            'apiVersion': 'ts-phone-api/3',
            'data': <Object?>[
              <String, Object?>{
                'sessionId': 'session-history',
                'sessionRevision': '33333333-3333-4333-8333-333333333333',
                'runtimeState': 'offline',
                'isStreaming': false,
                'accessMode': 'observer',
                'historyAvailable': true,
                'historyOnly': true,
                'canPrompt': false,
              },
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(api.close);

    final session = (await api.listSessions('ts_001')).single;
    expect(session.historyAvailable, isTrue);
    expect(session.historyOnly, isTrue);
    expect(session.canPrompt, isFalse);
  });

  test('requests and parses a structured timeline page', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/sessions/session-test/timeline'));
        expect(request.url.queryParameters, <String, String>{
          'before': '0000000a',
          'limit': '500',
          'branch': '0000000f',
        });
        return http.Response(
          jsonEncode(<String, Object?>{
            'apiVersion': 'ts-phone-api/3',
            'data': <String, Object?>{
              'schemaVersion': 'ts-phone-timeline/1',
              'sessionId': 'session-test',
              'sessionRevision': '11111111-1111-4111-8111-111111111111',
              'items': <Object?>[
                <String, Object?>{
                  'id': '00000009',
                  'turnId': '00000001',
                  'kind': 'activity',
                  'activity': <String, Object?>{
                    'category': 'subagent',
                    'status': 'completed',
                    'title': 'subagent_run',
                    'role': 'compute',
                    'operation': 'inspect',
                    'nodeRefs': <String>['node_1'],
                    'durationMs': 1200,
                    'totalTokens': 42,
                  },
                },
              ],
              'history': <String, Object?>{
                'totalItems': 3,
                'messageCount': 2,
                'activityCount': 1,
                'turnCount': 1,
                'branchCount': 1,
                'activeBranchId': '0000000f',
                'selectedBranchId': '0000000f',
                'branches': <Object?>[
                  <String, Object?>{
                    'id': '0000000f',
                    'active': true,
                    'itemCount': 3,
                    'messageCount': 2,
                    'activityCount': 1,
                    'turnCount': 1,
                  },
                ],
              },
              'hasMore': true,
              'nextBefore': '00000009',
              'lastEventId': 'epoch:12',
              'capabilities': <String>[
                timelineCapability,
                timelinePaginationCapability,
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final snapshot = await api.getTimeline(
      'ts_001',
      'session-test',
      before: '0000000a',
      limit: 500,
      branch: '0000000f',
    );
    expect(snapshot.items.single, isA<TimelineActivityItem>());
    final activity = (snapshot.items.single as TimelineActivityItem).activity;
    expect(activity.role, 'compute');
    expect(activity.totalTokens, 42);
    expect(snapshot.history.totalItems, 3);
    expect(snapshot.history.selectedBranchIsActive, isTrue);
    expect(snapshot.hasMore, isTrue);
  });

  test('does not follow redirects carrying credentials', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async => http.Response('', 302)),
    );
    addTearDown(api.close);

    await expectLater(
      api.listWorkspaces(),
      throwsA(
        isA<TsPhoneApiException>().having(
          (error) => error.statusCode,
          'status',
          302,
        ),
      ),
    );
  });

  test('aborts a stalled API request after the configured timeout', () async {
    final api = TsPhoneApi(
      settings,
      requestTimeout: const Duration(milliseconds: 20),
      client: MockClient((request) => Completer<http.Response>().future),
    );
    addTearDown(api.close);

    await expectLater(
      api.listWorkspaces(),
      throwsA(
        isA<TsPhoneApiException>().having(
          (error) => error.code,
          'code',
          'request_timeout',
        ),
      ),
    );
  });
}
