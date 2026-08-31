import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/models/workspace.dart';

void main() {
  test(
    'loads the complete bounded timeline and preserves research activity',
    () async {
      final api = FakeGateway();
      api.timelineResponder = ({before, branch}) async {
        if (before == null) {
          return timelineSnapshot(
            items: <SessionTimelineItem>[
              TimelineActivityItem(
                id: '00000003',
                turnId: '00000001',
                activity: const TimelineActivity(
                  category: TimelineActivityCategory.subagent,
                  status: TimelineActivityStatus.completed,
                  title: 'subagent_run',
                  role: 'compute',
                ),
              ),
              TimelineMessageItem(
                id: '00000004',
                turnId: '00000001',
                message: ChatMessage.fromJson(assistantMessage('latest')),
              ),
            ],
            totalItems: 4,
            hasMore: true,
            nextBefore: '00000003',
          );
        }
        expect(before, '00000003');
        return timelineSnapshot(
          items: <SessionTimelineItem>[
            TimelineMessageItem(
              id: '00000001',
              turnId: '00000001',
              message: ChatMessage.fromJson(userMessage('first turn')),
            ),
            TimelineMessageItem(
              id: '00000002',
              turnId: '00000001',
              message: ChatMessage.fromJson(assistantMessage('earlier')),
            ),
          ],
          totalItems: 4,
        );
      };
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
        initialCapabilities: const <String>{timelineCapability},
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(api.timelineCalls, 2);
      expect(controller.loadedTimelineItemCount, 4);
      expect(
        controller.timelineItems.whereType<TimelineActivityItem>(),
        hasLength(1),
      );
      expect(controller.messages.map((message) => message.text), <String>[
        'first turn',
        'earlier',
        'latest',
      ]);
      expect(controller.canLoadEarlierMessages, isFalse);
    },
  );

  test('an inactive timeline branch is read-only', () async {
    final api = FakeGateway();
    api.timelineResponder = ({before, branch}) async => timelineSnapshot(
      items: <SessionTimelineItem>[
        TimelineMessageItem(
          id: branch == '00000002' ? '00000002' : '00000003',
          turnId: '00000001',
          message: ChatMessage.fromJson(
            assistantMessage(branch == '00000002' ? 'alternate' : 'active'),
          ),
        ),
      ],
      totalItems: 1,
      selectedBranchId: branch ?? '00000003',
      includeCommands: branch != '00000002',
      branches: const <TimelineBranchSummary>[
        TimelineBranchSummary(
          id: '00000002',
          active: false,
          itemCount: 1,
          messageCount: 1,
          activityCount: 0,
          turnCount: 1,
        ),
        TimelineBranchSummary(
          id: '00000003',
          active: true,
          itemCount: 1,
          messageCount: 1,
          activityCount: 0,
          turnCount: 1,
        ),
      ],
    );
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
      initialCapabilities: const <String>{timelineCapability},
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.viewingInactiveBranch, isFalse);

    await controller.selectTimelineBranch('00000002');

    expect(controller.viewingInactiveBranch, isTrue);
    expect(controller.messages.single.text, 'alternate');
    expect(controller.canSend, isFalse);

    api.addEvent('session_state', <String, Object?>{
      'state': 'idle',
      'canPrompt': true,
      'capabilities': <String>[timelineCapability, promptCapability],
    });
    api.addEvent('input', <String, Object?>{'text': 'active prompt'});
    api.addEvent('message_end', <String, Object?>{
      'message': assistantMessage('active reply'),
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.single.text, 'alternate');
    expect(controller.canSend, isFalse);
  });

  test(
    'load all history traverses every page above the automatic limit',
    () async {
      const totalItems = 2501;
      final api = FakeGateway();
      api.timelineResponder = ({before, branch}) async {
        final end = before == null
            ? totalItems
            : int.parse(before, radix: 16) - 1;
        final candidateStart = end - 499;
        final start = candidateStart < 1 ? 1 : candidateStart;
        final items = <SessionTimelineItem>[
          for (var id = start; id <= end; id += 1)
            TimelineMessageItem(
              id: id.toRadixString(16).padLeft(8, '0'),
              turnId: '00000001',
              message: ChatMessage.fromJson(assistantMessage('message-$id')),
            ),
        ];
        return timelineSnapshot(
          items: items,
          totalItems: totalItems,
          hasMore: start > 1,
          nextBefore: start > 1 ? items.first.id : null,
        );
      };
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
        initialCapabilities: const <String>{timelineCapability},
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.loadedTimelineItemCount, 500);
      expect(controller.canLoadEarlierMessages, isTrue);

      await controller.loadAllHistory();

      expect(api.timelineCalls, 6);
      expect(controller.loadedTimelineItemCount, totalItems);
      expect(controller.timelineItems.first.id, '00000001');
      expect(controller.timelineItems.last.id, '000009c5');
      expect(controller.canLoadEarlierMessages, isFalse);
    },
  );

  test(
    'load all history stops when the timeline cursor does not advance',
    () async {
      final api = FakeGateway();
      api.timelineResponder = ({before, branch}) async => timelineSnapshot(
        items: <SessionTimelineItem>[
          TimelineMessageItem(
            id: '0000000a',
            turnId: '00000001',
            message: ChatMessage.fromJson(assistantMessage('latest')),
          ),
        ],
        totalItems: 2501,
        hasMore: true,
        nextBefore: '0000000a',
      );
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
        initialCapabilities: const <String>{timelineCapability},
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.loadAllHistory();

      expect(api.timelineCalls, 2);
      expect(controller.problem?.kind, TsPhoneProblemKind.incompatible);
      expect(controller.problem?.code, TsPhoneProblemCode.incompatible);
      expect(controller.loadingAllHistory, isFalse);
    },
  );

  test('persisted timeline replaces equivalent transient messages', () async {
    var persisted = false;
    final api = FakeGateway();
    api.timelineResponder = ({before, branch}) async => timelineSnapshot(
      items: <SessionTimelineItem>[
        TimelineMessageItem(
          id: '00000001',
          turnId: '00000001',
          message: ChatMessage.fromJson(userMessage('existing')),
        ),
        if (persisted)
          TimelineMessageItem(
            id: '00000002',
            turnId: '00000002',
            message: ChatMessage.fromJson(<String, Object?>{
              'role': 'user',
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'CLI prompt'},
              ],
              'timestamp': DateTime.utc(2026, 8, 15).millisecondsSinceEpoch,
            }),
          ),
        if (persisted)
          TimelineMessageItem(
            id: '00000003',
            turnId: '00000002',
            message: ChatMessage.fromJson(assistantMessage('complete reply')),
          ),
      ],
      totalItems: persisted ? 3 : 1,
    );
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
      initialCapabilities: const <String>{timelineCapability},
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    api.addEvent('input', <String, Object?>{'text': 'CLI prompt'});
    api.addEvent('message_end', <String, Object?>{
      'message': assistantMessage('complete reply'),
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.timelineItems, hasLength(3));
    expect(
      controller.timelineItems.where(
        (item) => !RegExp(r'^[0-9a-f]{8}$').hasMatch(item.id),
      ),
      hasLength(2),
    );

    persisted = true;
    await controller.refreshMessages();

    expect(controller.timelineItems, hasLength(3));
    expect(controller.loadedTimelineItemCount, 3);
    expect(controller.messages.map((message) => message.text), <String>[
      'existing',
      'CLI prompt',
      'complete reply',
    ]);
  });

  test('loads offline disk history without enabling phone commands', () async {
    final api = FakeGateway()
      ..snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[userMessage('restored history')],
        lastEventId: 'epoch:0',
      );
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.observer,
      initialRuntimeState: RuntimeState.offline,
      initialHistoryAvailable: true,
      initialCanPrompt: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(api.messageSnapshotCalls, 1);
    expect(controller.messages.single.text, 'restored history');
    expect(controller.historyOnly, isTrue);
    expect(controller.canRefresh, isTrue);
    expect(controller.canSend, isFalse);
    expect(await controller.send('must not send'), isFalse);
    expect(api.lastMessage, isNull);

    api.addEvent('session_state', <String, Object?>{
      'state': 'idle',
      'isStreaming': false,
      'historyAvailable': true,
      'historyOnly': false,
      'canPrompt': true,
      'accessMode': 'controller',
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.historyOnly, isFalse);
    expect(controller.accessMode, SessionAccessMode.controller);
    expect(controller.canSend, isTrue);
  });

  test('prepends earlier pages and keeps them across live snapshots', () async {
    final api = FakeGateway()
      ..snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[
          userMessage('current-10'),
          assistantMessage('current-11'),
        ],
        messageIds: const <String>['0000000a', '0000000b'],
        hasMore: true,
        nextBefore: '0000000a',
        lastEventId: 'epoch:0',
      )
      ..earlierSnapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[
          userMessage('earlier-8'),
          assistantMessage('earlier-9'),
        ],
        messageIds: const <String>['00000008', '00000009'],
        lastEventId: 'epoch:0',
      );
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.canLoadEarlierMessages, isTrue);
    expect(await controller.loadEarlierMessages(), isTrue);
    expect(api.lastBefore, '0000000a');
    expect(api.lastLimit, 200);
    expect(controller.messages.map((message) => message.text), <String>[
      'earlier-8',
      'earlier-9',
      'current-10',
      'current-11',
    ]);
    expect(controller.canLoadEarlierMessages, isFalse);

    api.addEvent('session.snapshot', <String, Object?>{
      'sessionId': 'session-test',
      'isStreaming': false,
      'messages': <Object?>[
        userMessage('current-10'),
        assistantMessage('current-11'),
        assistantMessage('current-12'),
      ],
      'messageIds': <String>['0000000a', '0000000b', '0000000c'],
      'hasMore': true,
      'nextBefore': '0000000a',
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.map((message) => message.text), <String>[
      'earlier-8',
      'earlier-9',
      'current-10',
      'current-11',
      'current-12',
    ]);
    expect(controller.canLoadEarlierMessages, isFalse);
  });

  test('replaces abandoned messages when the live Pi branch changes', () async {
    final api = FakeGateway()
      ..snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[
          userMessage('root'),
          assistantMessage('shared'),
          assistantMessage('abandoned'),
        ],
        messageIds: const <String>['00000001', '00000002', '00000003'],
        lastEventId: 'epoch:0',
      );
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    api.addEvent('session.snapshot', <String, Object?>{
      'sessionId': 'session-test',
      'isStreaming': false,
      'messages': <Object?>[
        userMessage('root'),
        assistantMessage('shared'),
        assistantMessage('active branch'),
      ],
      'messageIds': <String>['00000001', '00000002', '00000004'],
      'hasMore': false,
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.map((message) => message.text), <String>[
      'root',
      'shared',
      'active branch',
    ]);
  });

  test(
    'mirrors CLI input and sends phone prompts to the same session',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.messages.single.text, 'existing');
      expect(api.lastEventIds, <String?>['epoch:0']);

      api.addEvent('input', <String, Object?>{
        'type': 'input',
        'text': 'CLI prompt',
        'source': 'interactive',
        'origin': 'local',
      });
      api.addEvent('agent_start', <String, Object?>{'type': 'agent_start'});
      api.addEvent('message_start', <String, Object?>{
        'type': 'message_start',
        'message': <String, Object?>{'role': 'assistant'},
      });
      api.addEvent('message_update', <String, Object?>{
        'type': 'message_update',
        'assistantMessageEvent': <String, Object?>{
          'type': 'text_delta',
          'delta': 'streamed',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.messages.last.text, 'CLI prompt');
      expect(controller.runtimeState, RuntimeState.running);
      expect(controller.streamingText, 'streamed');
      expect(await controller.send('phone prompt'), isTrue);
      expect(api.lastMessage, 'phone prompt');
    },
  );

  test('surfaces each phone approval once', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final requestFuture = controller.uiRequests.first;
    final payload = <String, Object?>{
      'id': 'approval-1',
      'method': 'confirm',
      'toolName': 'bash',
      'preview': 'Tool: bash',
      'turnId': 'turn-1',
      'toolCallId': 'tool-1',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 1))
          .toIso8601String(),
    };
    api.addEvent('approval.request', payload);
    api.addEvent('approval.request', payload);
    final request = await requestFuture;
    expect(request.preview, 'Tool: bash');
    expect(request.toolName, 'bash');
    expect(request.sessionRevision, '11111111-1111-4111-8111-111111111111');
    expect(await controller.respondToUi(request, approved: true), isNull);
    expect(api.lastApprovalId, 'approval-1');
    expect(api.lastApproval, isTrue);
  });

  test('rejects malformed optional approval identity fields', () {
    expect(
      () => ExtensionUiRequest.fromJson(<String, Object?>{
        'id': 'approval-invalid',
        'method': 'confirm',
        'toolName': 'bash',
        'preview': 'Tool: bash',
        'turnId': 42,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      }, sessionRevision: '11111111-1111-4111-8111-111111111111'),
      throwsFormatException,
    );
  });

  test('reconciles an optimistic phone message by client message id', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
      clientMessageIdFactory: () => 'phone-message-1',
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(await controller.send('phone prompt'), isTrue);
    expect(controller.messages.last.text, 'phone prompt');
    expect(
      controller.messages.last.deliveryState,
      ChatDeliveryState.synchronizing,
    );

    api.addEvent('input', <String, Object?>{
      'type': 'input',
      'text': 'phone prompt',
      'origin': 'phone',
      'clientMessageId': 'phone-message-1',
    });
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.messages.where((message) => message.text == 'phone prompt'),
      hasLength(1),
    );
    expect(controller.messages.last.deliveryState, isNull);
    expect(controller.messages.last.origin, 'phone');
  });

  test(
    'removes a failed optimistic message so the draft can be retried',
    () async {
      final api = FakeGateway()
        ..sendError = const TsPhoneApiException(
          'Unavailable',
          statusCode: 503,
          code: 'service_unavailable',
        );
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
        clientMessageIdFactory: () => 'phone-message-failed',
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(await controller.send('retry me'), isFalse);
      expect(
        controller.messages.any((message) => message.text == 'retry me'),
        isFalse,
      );
      expect(controller.problem?.code, TsPhoneProblemCode.serviceUnavailable);
    },
  );

  test('scopes approval deduplication to the session revision', () async {
    const nextRevision = '22222222-2222-4222-8222-222222222222';
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final payload = <String, Object?>{
      'id': 'approval-reused',
      'method': 'confirm',
      'toolName': 'bash',
      'preview': 'Tool: bash',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 1))
          .toIso8601String(),
    };

    final firstFuture = controller.uiRequests.first;
    api.addEvent('approval.request', payload);
    expect((await firstFuture).sessionRevision, controller.sessionRevision);

    api.nextSnapshot = Future<TsPhoneMessageSnapshot>.value(
      const TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: nextRevision,
        messages: <Object?>[],
        lastEventId: 'next-epoch:1',
      ),
    );
    api.addEvent('session_state', <String, Object?>{
      'state': 'idle',
    }, sessionRevision: nextRevision);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final secondFuture = controller.uiRequests.first;
    api.addEvent('approval.request', payload, sessionRevision: nextRevision);
    expect((await secondFuture).sessionRevision, nextRevision);
  });

  test('does not send while the TSPi bridge is offline', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.offline,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.canSend, isFalse);
    expect(await controller.send('must not leave the phone'), isFalse);
    expect(api.lastMessage, isNull);
  });

  test(
    'suspends and immediately resumes one event stream without stale errors',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
        eventErrorDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.eventConnectionState, EventConnectionState.connected);
      expect(api.eventConnectionCount, 1);

      api.addEvent('agent_start', <String, Object?>{'type': 'agent_start'});
      await Future<void>.delayed(Duration.zero);
      api.failEventStream();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        controller.eventConnectionState,
        EventConnectionState.reconnecting,
      );
      expect(controller.problem?.code, TsPhoneProblemCode.networkRetrying);
      expect(controller.canSend, isFalse);

      controller.suspendEventStream();
      expect(controller.eventConnectionState, EventConnectionState.suspended);
      expect(controller.problem, isNull);
      controller.resumeEventStream();
      await Future<void>.delayed(Duration.zero);
      expect(controller.eventConnectionState, EventConnectionState.connected);
      expect(controller.problem, isNull);
      expect(api.eventConnectionCount, 2);
      expect(api.lastEventIds, <String?>['epoch:0', 'epoch:0']);
    },
  );

  test(
    'refresh reconnects from its checkpoint without duplicating completed messages',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final reply = assistantMessage('completed once');
      api.addEvent('message_end', <String, Object?>{
        'type': 'message_end',
        'message': reply,
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.messages.where(
          (message) => message.text == 'completed once',
        ),
        hasLength(1),
      );

      api.snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[userMessage('existing'), reply],
        lastEventId: 'epoch:1',
      );
      await controller.refreshMessages();
      await Future<void>.delayed(Duration.zero);

      expect(api.lastEventIds, <String?>['epoch:0', 'epoch:1']);
      expect(
        controller.messages.where(
          (message) => message.text == 'completed once',
        ),
        hasLength(1),
      );
    },
  );

  test('snapshot timeout clears synchronization and allows retry', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
      snapshotTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    api.nextSnapshot = Completer<TsPhoneMessageSnapshot>().future;
    await controller.refreshMessages();

    expect(controller.isSynchronizing, isFalse);
    expect(controller.canSend, isFalse);
    expect(controller.problem?.code, TsPhoneProblemCode.requestTimeout);

    await controller.refreshMessages();
    expect(controller.isSynchronizing, isFalse);
    expect(controller.canSend, isTrue);
    expect(controller.problem, isNull);
  });

  test(
    'resume waits for a fresh snapshot before opening the next event stream',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.suspendEventStream();

      final snapshot = Completer<TsPhoneMessageSnapshot>();
      api.nextSnapshot = snapshot.future;
      controller.resumeEventStream();
      await Future<void>.delayed(Duration.zero);
      expect(api.eventConnectionCount, 1);

      snapshot.complete(
        TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: '11111111-1111-4111-8111-111111111111',
          messages: <Object?>[userMessage('after resume')],
          lastEventId: 'epoch:8',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.eventConnectionCount, 2);
      expect(api.lastEventIds, <String?>['epoch:0', 'epoch:8']);
      expect(controller.messages.single.text, 'after resume');
    },
  );

  test(
    'session revision change discards the stale event and resynchronizes',
    () async {
      const nextRevision = '22222222-2222-4222-8222-222222222222';
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      api.nextSnapshot = Future<TsPhoneMessageSnapshot>.value(
        const TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: nextRevision,
          messages: <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'new authoritative'},
              ],
              'timestamp': 1,
            },
          ],
          lastEventId: 'next-epoch:1',
        ),
      );
      api.addEvent('input', <String, Object?>{
        'text': 'must not be appended',
      }, sessionRevision: nextRevision);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.sessionRevision, nextRevision);
      expect(controller.messages.single.text, 'new authoritative');
      expect(
        controller.messages.any(
          (message) => message.text == 'must not be appended',
        ),
        isFalse,
      );
      expect(api.lastEventIds.last, 'next-epoch:1');
    },
  );

  test(
    'shows tool results delivered by message_end during a running turn',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      api.addEvent('message_end', <String, Object?>{
        'type': 'message_end',
        'message': <String, Object?>{
          'role': 'toolResult',
          'toolName': 'read',
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'tool output'},
          ],
          'isError': false,
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.messages.last.role, ChatRole.tool);
      expect(controller.messages.last.tools.single.body, 'tool output');
    },
  );

  test(
    'keeps sending disabled until an offline workspace finishes synchronizing',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.offline,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final snapshot = Completer<TsPhoneMessageSnapshot>();
      api.nextSnapshot = snapshot.future;
      api.addEvent('session_state', <String, Object?>{
        'state': 'idle',
        'isStreaming': false,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.runtimeState, RuntimeState.idle);
      expect(controller.isSynchronizing, isTrue);
      expect(controller.canSend, isFalse);

      snapshot.complete(
        TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: '11111111-1111-4111-8111-111111111111',
          messages: <Object?>[userMessage('restored safely')],
          lastEventId: 'epoch:9',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.isSynchronizing, isFalse);
      expect(controller.canSend, isTrue);
      expect(controller.messages.single.text, 'restored safely');
      expect(api.lastEventIds.last, 'epoch:9');
    },
  );

  test('preserves completed messages when TSPi disconnects', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    api.addEvent('session_state', <String, Object?>{
      'state': 'offline',
      'isStreaming': false,
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.runtimeState, RuntimeState.offline);
    expect(controller.canSend, isFalse);
    expect(controller.messages.single.text, 'existing');
  });

  test('manual retry replaces the current event stream', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.offline,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(api.eventConnectionCount, 1);

    await controller.retryConnection();
    await Future<void>.delayed(Duration.zero);

    expect(api.eventConnectionCount, 2);
    expect(controller.eventConnectionState, EventConnectionState.connected);
    expect(controller.problem, isNull);
  });

  test('snapshot failure keeps input disabled after SSE reconnects', () async {
    final snapshot = Completer<TsPhoneMessageSnapshot>();
    final api = FakeGateway()..nextSnapshot = snapshot.future;
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);

    final initialization = controller.initialize();
    snapshot.completeError(StateError('snapshot unavailable'));
    await initialization;
    await Future<void>.delayed(Duration.zero);

    expect(controller.eventConnectionState, EventConnectionState.connected);
    expect(controller.problem?.code, TsPhoneProblemCode.connectionFailed);
    expect(controller.canSend, isFalse);
    expect(await controller.send('must remain local'), isFalse);
    expect(api.lastMessage, isNull);
  });

  test(
    'isolates coalesced stream renders and flushes message_end immediately',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
        streamRenderInterval: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      api.addEvent('message_start', <String, Object?>{
        'message': <String, Object?>{'role': 'assistant'},
      });
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      var streamNotifications = 0;
      controller.addListener(() => notifications += 1);
      controller.streamingTextUpdates.addListener(
        () => streamNotifications += 1,
      );
      api.addEvent('message_update', <String, Object?>{
        'assistantMessageEvent': <String, Object?>{
          'type': 'thinking_delta',
          'delta': 'not rendered',
        },
      });
      for (final delta in <String>['a', 'b', 'c', 'd']) {
        api.addEvent('message_update', <String, Object?>{
          'assistantMessageEvent': <String, Object?>{
            'type': 'text_delta',
            'delta': delta,
          },
        });
      }
      await Future<void>.delayed(Duration.zero);

      expect(controller.streamingText, 'abcd');
      expect(notifications, 0);
      expect(streamNotifications, 0);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications, 0);
      expect(streamNotifications, 1);
      expect(controller.streamingTextUpdates.value, 'abcd');

      notifications = 0;
      streamNotifications = 0;
      api.addEvent('message_update', <String, Object?>{
        'assistantMessageEvent': <String, Object?>{
          'type': 'text_delta',
          'delta': ' pending',
        },
      });
      api.addEvent('message_end', <String, Object?>{
        'message': assistantMessage('complete'),
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.streamingText, isNull);
      expect(controller.messages.last.text, 'complete');
      expect(notifications, 1);
      expect(streamNotifications, 1);
      expect(controller.streamingTextUpdates.value, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications, 1);
      expect(streamNotifications, 1);
    },
  );

  test(
    'publishes timeline updates only when completed messages change',
    () async {
      final api = FakeGateway();
      final controller = ChatController(
        api: api,
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        initialSessionRevision: '11111111-1111-4111-8111-111111111111',
        accessMode: SessionAccessMode.controller,
        initialRuntimeState: RuntimeState.idle,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      var timelineNotifications = 0;
      controller.messagesUpdates.addListener(() => timelineNotifications += 1);
      api.addEvent('tool_execution_start', <String, Object?>{
        'toolName': 'read',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.activity?.kind, ChatActivityKind.runningTool);
      expect(controller.activity?.toolName, 'read');
      expect(timelineNotifications, 0);

      api.addEvent('input', <String, Object?>{'text': 'new prompt'});
      await Future<void>.delayed(Duration.zero);
      expect(timelineNotifications, 1);
      expect(controller.messagesUpdates.value.last.text, 'new prompt');
    },
  );

  test('bounds the live preview while retaining the complete stream', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
      streamRenderInterval: const Duration(milliseconds: 5),
      streamPreviewCharacterLimit: 8,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    api.addEvent('message_start', <String, Object?>{
      'message': <String, Object?>{'role': 'assistant'},
    });
    api.addEvent('message_update', <String, Object?>{
      'assistantMessageEvent': <String, Object?>{
        'type': 'text_delta',
        'delta': 'abc😀defghij',
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(controller.streamingText, 'abc😀defghij');
    expect(controller.streamingTextUpdates.value, startsWith('...\n\n'));
    expect(controller.streamingTextUpdates.value, endsWith('defghij'));
    expect(controller.streamingTextUpdates.value, isNot(contains('\uFFFD')));

    api.addEvent('message_end', <String, Object?>{
      'message': assistantMessage('complete full response'),
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.streamingTextUpdates.value, isNull);
    expect(controller.messages.last.text, 'complete full response');
  });

  test('updates model context from live session runtime events', () async {
    final api = FakeGateway();
    final controller = ChatController(
      api: api,
      workspaceId: 'ts_001',
      sessionId: 'session-test',
      initialSessionRevision: '11111111-1111-4111-8111-111111111111',
      accessMode: SessionAccessMode.controller,
      initialRuntimeState: RuntimeState.idle,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    api.addEvent('session_state', <String, Object?>{
      'state': 'idle',
      'runtime': sessionRuntimeJson(modelId: 'gpt-5.6-sol', usedTokens: 78214),
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.sessionRuntime?.model.id, 'gpt-5.6-sol');
    expect(controller.sessionRuntime?.context?.usedTokens, 78214);

    api.addEvent('session.snapshot', <String, Object?>{
      'isStreaming': false,
      'messages': <Object?>[],
      'runtime': sessionRuntimeJson(modelId: 'gpt-5.6-sol', usedTokens: null),
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.sessionRuntime?.context?.usedTokens, isNull);
    expect(controller.sessionRuntime?.context?.limitTokens, 128000);
  });
}

Map<String, Object?> sessionRuntimeJson({
  required String modelId,
  required int? usedTokens,
}) => <String, Object?>{
  'schemaVersion': 'ts-phone-session-runtime/1',
  'model': <String, Object?>{'provider': 'cpa', 'id': modelId},
  'context': <String, Object?>{
    'usedTokens': usedTokens,
    'limitTokens': 128000,
    'measurement': 'pi_estimate',
  },
  'updatedAt': '2026-08-31T06:32:18.000Z',
};

class FakeGateway implements TsPhoneGateway {
  final StreamController<TsPhoneEvent> _events =
      StreamController<TsPhoneEvent>.broadcast();
  int _sequence = 0;
  int eventConnectionCount = 0;
  int messageSnapshotCalls = 0;
  final List<String?> lastEventIds = <String?>[];
  String? lastMessage;
  Object? sendError;
  String? lastApprovalId;
  bool? lastApproval;
  TsPhoneMessageSnapshot snapshot = TsPhoneMessageSnapshot(
    sessionId: 'session-test',
    sessionRevision: '11111111-1111-4111-8111-111111111111',
    messages: <Object?>[userMessage('existing')],
    lastEventId: 'epoch:0',
  );
  TsPhoneMessageSnapshot? earlierSnapshot;
  String? lastBefore;
  int? lastLimit;
  Future<TsPhoneMessageSnapshot>? nextSnapshot;
  int timelineCalls = 0;
  Future<TsPhoneTimelineSnapshot> Function({String? before, String? branch})?
  timelineResponder;

  void addEvent(
    String type,
    Object? payload, {
    String sessionRevision = '11111111-1111-4111-8111-111111111111',
  }) {
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: sessionRevision,
        instanceEpoch: 'instance-1',
        sessionGeneration: 1,
        type: type,
        payload: payload,
        at: DateTime.utc(2026, 8, 15),
      ),
    );
  }

  void failEventStream() {
    _events.addError(StateError('network suspended'));
  }

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId,
    String sessionRevision,
  ) async {}

  @override
  void close() {
    unawaited(_events.close());
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) {
    eventConnectionCount += 1;
    lastEventIds.add(lastEventId);
    onConnected?.call();
    return _events.stream;
  }

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) {
    messageSnapshotCalls += 1;
    lastBefore = before;
    lastLimit = limit;
    final earlier = earlierSnapshot;
    if (before != null && earlier != null) {
      return Future<TsPhoneMessageSnapshot>.value(earlier);
    }
    final pending = nextSnapshot;
    nextSnapshot = null;
    return pending ?? Future<TsPhoneMessageSnapshot>.value(snapshot);
  }

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) {
    timelineCalls += 1;
    final responder = timelineResponder;
    if (responder == null) {
      throw UnsupportedError('Timeline is not configured for this test');
    }
    return responder(before: before, branch: branch);
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      const <WorkspaceSummary>[];

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async =>
      const <SessionSummary>[];

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async {
    lastApprovalId = approvalId;
    lastApproval = approved;
  }

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) async {
    if (sendError case final error?) throw error;
    lastMessage = message;
  }

  @override
  Future<Map<String, Object?>> version() async => <String, Object?>{};
}

Map<String, Object?> userMessage(String text) => <String, Object?>{
  'role': 'user',
  'content': <Object?>[
    <String, Object?>{'type': 'text', 'text': text},
  ],
  'timestamp': 1,
};

Map<String, Object?> assistantMessage(String text) => <String, Object?>{
  'role': 'assistant',
  'content': <Object?>[
    <String, Object?>{'type': 'text', 'text': text},
  ],
  'timestamp': 2,
};

TsPhoneTimelineSnapshot timelineSnapshot({
  required List<SessionTimelineItem> items,
  required int totalItems,
  bool hasMore = false,
  String? nextBefore,
  String selectedBranchId = '00000003',
  bool includeCommands = true,
  List<TimelineBranchSummary>? branches,
}) {
  final resolvedBranches =
      branches ??
      const <TimelineBranchSummary>[
        TimelineBranchSummary(
          id: '00000003',
          active: true,
          itemCount: 4,
          messageCount: 3,
          activityCount: 1,
          turnCount: 1,
        ),
      ];
  return TsPhoneTimelineSnapshot(
    sessionId: 'session-test',
    sessionRevision: '11111111-1111-4111-8111-111111111111',
    items: items,
    history: TimelineHistorySummary(
      totalItems: totalItems,
      messageCount: totalItems,
      activityCount: 0,
      turnCount: 1,
      activeBranchId: '00000003',
      selectedBranchId: selectedBranchId,
      branches: resolvedBranches,
    ),
    hasMore: hasMore,
    nextBefore: nextBefore,
    lastEventId: 'epoch:0',
    capabilities: <String>{
      timelineCapability,
      timelinePaginationCapability,
      timelineBranchesCapability,
      if (includeCommands) promptCapability,
      if (includeCommands) abortCapability,
    },
  );
}
