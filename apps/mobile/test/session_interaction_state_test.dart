import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/session_view_state.dart';
import 'package:ts_phone/features/chat/timeline_widgets.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/models/workspace.dart';

void main() {
  test('session state gives failures and recovery one stable priority', () {
    final failed = resolveSessionViewState(
      runtimeState: RuntimeState.running,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.serviceUnavailable,
      ),
      historyOnly: false,
      viewingInactiveBranch: false,
      canSend: true,
      hasActiveAgentRun: true,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(failed.phase, SessionUiPhase.failed);
    expect(failed.notice, SessionNoticeKind.error);
    expect(failed.canCompose, isFalse);
    expect(failed.canAbort, isFalse);

    final recovery = resolveSessionViewState(
      runtimeState: RuntimeState.recoveryRequired,
      eventConnectionState: EventConnectionState.reconnecting,
      isSynchronizing: false,
      problem: null,
      recoveredSession: true,
      historyOnly: false,
      viewingInactiveBranch: false,
      canSend: false,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(recovery.phase, SessionUiPhase.recovery);
    expect(recovery.notice, SessionNoticeKind.recovery);
    expect(recovery.isHistorical, isFalse);
  });

  test('session state exposes only the current turn action', () {
    final running = resolveSessionViewState(
      runtimeState: RuntimeState.running,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: null,
      historyOnly: false,
      viewingInactiveBranch: false,
      canSend: true,
      hasActiveAgentRun: true,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(running.phase, SessionUiPhase.running);
    expect(running.canAbort, isTrue);
    expect(running.canCompose, isTrue);

    final readOnlyRunning = resolveSessionViewState(
      runtimeState: RuntimeState.running,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: null,
      historyOnly: false,
      viewingInactiveBranch: false,
      canSend: false,
      hasActiveAgentRun: true,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(readOnlyRunning.phase, SessionUiPhase.running);
    expect(readOnlyRunning.canAbort, isFalse);

    final history = resolveSessionViewState(
      runtimeState: RuntimeState.offline,
      eventConnectionState: EventConnectionState.closed,
      isSynchronizing: false,
      problem: null,
      historyOnly: true,
      viewingInactiveBranch: false,
      canSend: false,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(history.phase, SessionUiPhase.history);
    expect(history.notice, isNull);
    expect(history.canCompose, isFalse);
    expect(history.isHistorical, isTrue);

    final promptableObserver = resolveSessionViewState(
      runtimeState: RuntimeState.idle,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: null,
      historyOnly: false,
      viewingInactiveBranch: false,
      canSend: true,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(promptableObserver.phase, SessionUiPhase.ready);
    expect(promptableObserver.isHistorical, isFalse);
    expect(promptableObserver.canCompose, isTrue);
    expect(promptableObserver.canAbort, isFalse);
  });

  test('a recovered page becomes ready after the runtime recovers', () {
    final state = resolveSessionViewState(
      runtimeState: RuntimeState.idle,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: null,
      recoveredSession: true,
      historyOnly: false,
      viewingInactiveBranch: false,
      canSend: true,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );

    expect(state.phase, SessionUiPhase.ready);
    expect(state.notice, isNull);
    expect(state.canCompose, isTrue);
  });

  test(
    'timeline grouping preserves order and assigns partial-page numbers',
    () {
      final items = <SessionTimelineItem>[
        TimelineMessageItem(
          id: '00000001',
          turnId: '00000001',
          message: ChatMessage(role: ChatRole.user, text: 'first'),
        ),
        const TimelineActivityItem(
          id: '00000002',
          turnId: '00000001',
          activity: TimelineActivity(
            category: TimelineActivityCategory.research,
            status: TimelineActivityStatus.completed,
            title: 'research_activity',
          ),
        ),
        TimelineMessageItem(
          id: '00000003',
          turnId: '00000002',
          message: ChatMessage(role: ChatRole.assistant, text: 'second'),
        ),
        const TimelineActivityItem(
          id: '00000004',
          activity: TimelineActivity(
            category: TimelineActivityCategory.system,
            status: TimelineActivityStatus.recorded,
            title: 'system',
          ),
        ),
      ];

      final groups = groupTimelineItems(items, totalTurnCount: 4);

      expect(groups, hasLength(3));
      expect(groups[0].turnId, '00000001');
      expect(groups[0].number, 3);
      expect(groups[0].activityCount, 1);
      expect(groups[1].turnId, '00000002');
      expect(groups[1].number, 4);
      expect(groups[2].turnId, isNull);
      expect(groups[2].items.single.id, '00000004');
    },
  );

  test('unscoped activities stay separate lazy timeline rows', () {
    const activity = TimelineActivity(
      category: TimelineActivityCategory.system,
      status: TimelineActivityStatus.recorded,
      title: 'system',
    );
    final groups = groupTimelineItems(const <SessionTimelineItem>[
      TimelineActivityItem(id: '00000005', activity: activity),
      TimelineActivityItem(id: '00000006', activity: activity),
    ], totalTurnCount: 0);

    expect(groups, hasLength(2));
    expect(groups.every((group) => group.turnId == null), isTrue);
    expect(groups[0].items.single.id, '00000005');
    expect(groups[1].items.single.id, '00000006');
  });

  test('split turns have unique presentation identities', () {
    const activity = TimelineActivity(
      category: TimelineActivityCategory.system,
      status: TimelineActivityStatus.recorded,
      title: 'system',
    );
    final groups = groupTimelineItems(const <SessionTimelineItem>[
      TimelineMessageItem(
        id: '00000010',
        turnId: '00000001',
        message: ChatMessage(role: ChatRole.user, text: 'prompt'),
      ),
      TimelineActivityItem(id: '00000011', activity: activity),
      TimelineActivityItem(
        id: '00000012',
        turnId: '00000001',
        activity: activity,
      ),
    ], totalTurnCount: 1);

    expect(groups.map((group) => group.identity).toSet(), hasLength(3));
  });
}
