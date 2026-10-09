import 'package:flutter_test/flutter_test.dart';
import 'package:corhub/data/corhub_api.dart';
import 'package:corhub/features/chat/chat_controller.dart';
import 'package:corhub/features/chat/session_view_state.dart';
import 'package:corhub/models/workspace.dart';

void main() {
  test('session state gives failures and recovery one stable priority', () {
    final failed = resolveSessionViewState(
      runtimeState: RuntimeState.running,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: const CorHubProblem(
        CorHubProblemKind.unavailable,
        CorHubProblemCode.serviceUnavailable,
      ),
      historyOnly: false,
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
      canSend: false,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );
    expect(recovery.phase, SessionUiPhase.recovery);
    expect(recovery.notice, SessionNoticeKind.recovery);
    expect(recovery.isHistorical, isFalse);
  });

  test('background event retry stays in the app-bar connection state', () {
    final state = resolveSessionViewState(
      runtimeState: RuntimeState.idle,
      eventConnectionState: EventConnectionState.reconnecting,
      isSynchronizing: false,
      problem: const CorHubProblem(
        CorHubProblemKind.unavailable,
        CorHubProblemCode.networkRetrying,
      ),
      historyOnly: false,
      canSend: false,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );

    expect(state.phase, SessionUiPhase.reconnecting);
    expect(state.notice, isNull);
  });

  test('session state exposes only the current turn action', () {
    final running = resolveSessionViewState(
      runtimeState: RuntimeState.running,
      eventConnectionState: EventConnectionState.connected,
      isSynchronizing: false,
      problem: null,
      historyOnly: false,
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
      canSend: true,
      hasActiveAgentRun: false,
      commandInFlight: false,
      canRefresh: true,
    );

    expect(state.phase, SessionUiPhase.ready);
    expect(state.notice, isNull);
    expect(state.canCompose, isTrue);
  });
}
