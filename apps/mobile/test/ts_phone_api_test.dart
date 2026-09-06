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
            'apiVersion': 'ts-phone-api/4',
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
            'apiVersion': 'ts-phone-api/4',
            'data': <String, Object?>{
              'sessionId': 'session-test',
              'sessionRevision': '11111111-1111-4111-8111-111111111111',
              'activeAgentRunId': null,
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
            'apiVersion': 'ts-phone-api/4',
            'data': <String, Object?>{
              'sessionId': 'session-test',
              'sessionRevision': '11111111-1111-4111-8111-111111111111',
              'activeAgentRunId': null,
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
            'apiVersion': 'ts-phone-api/4',
            'data': <Object?>[
              <String, Object?>{
                'sessionId': 'session-history',
                'sessionRevision': '33333333-3333-4333-8333-333333333333',
                'activeAgentRunId': null,
                'runtimeState': 'offline',
                'isStreaming': false,
                'accessMode': 'observer',
                'historyAvailable': true,
                'historyOnly': true,
                'canPrompt': false,
                'runtime': <String, Object?>{
                  'schemaVersion': 'ts-phone-session-runtime/1',
                  'model': <String, Object?>{
                    'provider': 'cpa',
                    'id': 'gpt-5.6-sol',
                  },
                  'context': <String, Object?>{
                    'usedTokens': 78214,
                    'limitTokens': 128000,
                    'measurement': 'pi_estimate',
                  },
                  'updatedAt': '2026-08-31T06:32:18.000Z',
                },
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
    expect(session.runtime?.model.id, 'gpt-5.6-sol');
    expect(session.runtime?.context?.usedTokens, 78214);
    expect(session.runtime?.context?.limitTokens, 128000);
  });

  test('requests projects and sessions by lifecycle state', () async {
    var requestIndex = 0;
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.queryParameters, <String, String>{
          'state': 'archived',
        });
        final data = requestIndex++ == 0
            ? <Object?>[_workspaceJson(lifecycleState: 'archived')]
            : <Object?>[_sessionJson(lifecycleState: 'archived')];
        return _apiResponse(data);
      }),
    );
    addTearDown(api.close);

    final management = api as TsPhoneManagementGateway;
    final projects = await management.listWorkspacesByLifecycle(
      LifecycleState.archived,
    );
    final sessions = await management.listSessionsByLifecycle(
      'ts_001',
      LifecycleState.archived,
    );

    expect(projects.single.lifecycleState, LifecycleState.archived);
    expect(sessions.single.lifecycleState, LifecycleState.archived);
    expect(requestIndex, 2);
  });

  test('binds project creation, preflight, and purge requests', () async {
    var requestIndex = 0;
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        switch (requestIndex++) {
          case 0:
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v4/workspaces');
            expect(jsonDecode(request.body), <String, Object?>{
              'name': 'Catalytic cycle',
            });
            return _apiResponse(<String, Object?>{
              'workspace': _workspaceJson(),
              'session': _sessionJson(),
            }, statusCode: 201);
          case 1:
            expect(request.method, 'GET');
            expect(
              request.url.path,
              '/api/v4/workspaces/ts_001/deletion-preflight',
            );
            return _apiResponse(<String, Object?>{
              'workspaceId': 'ts_001',
              'managementRevision': _managementRevision,
              'activeWorkers': 0,
              'remoteCalculations': 0,
              'pendingApprovals': 0,
              'unresolvedRemoteEffects': 0,
              'canDelete': true,
            });
          case 2:
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v4/workspaces/ts_001/purge');
            expect(jsonDecode(request.body), <String, Object?>{
              'managementRevision': _managementRevision,
              'confirmation': 'ts_001',
            });
            return _apiResponse(<String, Object?>{'purged': true});
          default:
            fail(
              'Unexpected management request: ${request.method} ${request.url}',
            );
        }
      }),
    );
    addTearDown(api.close);

    final management = api as TsPhoneManagementGateway;
    final created = await management.createWorkspace('Catalytic cycle');
    final preflight = await management.workspaceDeletionPreflight('ts_001');
    await management.purgeWorkspace('ts_001', preflight.managementRevision);

    expect(created.workspace.id, 'ts_001');
    expect(created.session.sessionId, 'session_1');
    expect(preflight.canDelete, isTrue);
    expect(requestIndex, 3);
  });

  test('binds managed session creation and activation requests', () async {
    var requestIndex = 0;
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        if (requestIndex++ == 0) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v4/workspaces/ts_001/sessions');
          expect(jsonDecode(request.body), <String, Object?>{
            'accessMode': 'observer',
            'name': 'Review path',
            'model': 'cpa/gpt-5.6-sol',
          });
          return _apiResponse(
            _sessionJson(accessMode: 'observer'),
            statusCode: 201,
          );
        }
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v4/workspaces/ts_001/sessions/session_1/activate',
        );
        expect(jsonDecode(request.body), <String, Object?>{
          'managementRevision': _managementRevision,
        });
        return _apiResponse(
          _sessionJson(
            accessMode: 'observer',
            runtimeState: 'idle',
            canActivate: false,
            canPrompt: true,
          ),
        );
      }),
    );
    addTearDown(api.close);

    final management = api as TsPhoneManagementGateway;
    final created = await management.createSession(
      'ts_001',
      accessMode: SessionAccessMode.observer,
      name: 'Review path',
      model: 'cpa/gpt-5.6-sol',
    );
    final active = await management.activateSession(
      'ts_001',
      created.sessionId,
      created.managementRevision,
    );

    expect(active.runtimeState, RuntimeState.idle);
    expect(active.canPrompt, isTrue);
    expect(requestIndex, 2);
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
            'apiVersion': 'ts-phone-api/4',
            'data': <String, Object?>{
              'schemaVersion': 'ts-phone-timeline/1',
              'sessionId': 'session-test',
              'sessionRevision': '11111111-1111-4111-8111-111111111111',
              'activeAgentRunId': 'run-current',
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
    expect(snapshot.activeAgentRunId, 'run-current');
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

  test('binds an abort request to the active agent run', () async {
    final api = TsPhoneApi(
      settings,
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/v4/workspaces/ts_001/sessions/session-test/abort',
        );
        expect(jsonDecode(request.body), <String, Object?>{
          'sessionRevision': '11111111-1111-4111-8111-111111111111',
          'agentRunId': 'run-current',
        });
        return http.Response(
          jsonEncode(<String, Object?>{
            'apiVersion': 'ts-phone-api/4',
            'data': <String, Object?>{'aborted': true},
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    await api.abort(
      'ts_001',
      'session-test',
      sessionRevision: '11111111-1111-4111-8111-111111111111',
      agentRunId: 'run-current',
    );
  });

  test('classifies a stale abort target as a changed generation', () {
    final problem = describeTsPhoneProblem(
      const TsPhoneApiException(
        'stale',
        statusCode: 409,
        code: 'agent_run_stale',
      ),
    );
    expect(problem.code, TsPhoneProblemCode.agentRunChanged);
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

const _managementRevision = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

Map<String, Object?> _workspaceJson({String lifecycleState = 'active'}) =>
    <String, Object?>{
      'id': 'ts_001',
      'name': 'Catalytic cycle',
      'runtimeState': 'offline',
      'isStreaming': false,
      'liveSessionCount': 0,
      'sessionCount': 1,
      'lifecycleState': lifecycleState,
      'managementRevision': _managementRevision,
      'managed': true,
    };

Map<String, Object?> _sessionJson({
  String lifecycleState = 'active',
  String accessMode = 'controller',
  String runtimeState = 'offline',
  bool canActivate = true,
  bool canPrompt = false,
}) => <String, Object?>{
  'sessionId': 'session_1',
  'sessionRevision': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'activeAgentRunId': null,
  'runtimeState': runtimeState,
  'isStreaming': false,
  'accessMode': accessMode,
  'historyAvailable': false,
  'historyOnly': false,
  'canPrompt': canPrompt,
  'capabilities': <String>[],
  'lifecycleState': lifecycleState,
  'managementRevision': _managementRevision,
  'managed': true,
  'canActivate': canActivate,
};

http.Response _apiResponse(Object? data, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(<String, Object?>{
        'apiVersion': 'ts-phone-api/4',
        'data': data,
      }),
      statusCode,
    );
