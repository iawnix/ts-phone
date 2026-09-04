import '../../data/ts_phone_api.dart';
import '../../models/workspace.dart';
import 'chat_controller.dart';

/// The small, presentation-facing state machine for a chat session.
///
/// Transport details remain in [ChatController].  The page consumes this
/// derived state so that every state has one visual priority and one set of
/// available actions instead of repeating slightly different conditionals.
enum SessionUiPhase {
  failed,
  recovery,
  offline,
  history,
  synchronizing,
  running,
  reconnecting,
  ready,
}

enum SessionNoticeKind { error, recovery, offline }

final class SessionViewState {
  const SessionViewState({
    required this.phase,
    required this.notice,
    required this.canCompose,
    required this.canAbort,
    required this.canRefresh,
    required this.isHistorical,
  });

  factory SessionViewState.fromController(ChatController controller) {
    return resolveSessionViewState(
      runtimeState: controller.runtimeState,
      eventConnectionState: controller.eventConnectionState,
      isSynchronizing: controller.isSynchronizing,
      problem: controller.problem,
      recoveredSession: controller.recoveredSession,
      historyOnly: controller.historyOnly,
      viewingInactiveBranch: controller.viewingInactiveBranch,
      canSend: controller.canSend,
      commandInFlight: controller.commandInFlight,
      canRefresh: controller.canRefresh,
    );
  }

  final SessionUiPhase phase;
  final SessionNoticeKind? notice;
  final bool canCompose;
  final bool canAbort;
  final bool canRefresh;
  final bool isHistorical;

  bool get hasLiveRun => phase == SessionUiPhase.running;
  bool get isConnecting =>
      phase == SessionUiPhase.synchronizing ||
      phase == SessionUiPhase.reconnecting;
}

SessionViewState resolveSessionViewState({
  required RuntimeState runtimeState,
  required EventConnectionState eventConnectionState,
  required bool isSynchronizing,
  required TsPhoneProblem? problem,
  bool recoveredSession = false,
  required bool historyOnly,
  required bool viewingInactiveBranch,
  required bool canSend,
  required bool commandInFlight,
  required bool canRefresh,
}) {
  final phase = _resolvePhase(
    runtimeState: runtimeState,
    eventConnectionState: eventConnectionState,
    isSynchronizing: isSynchronizing,
    problem: problem,
    recoveredSession: recoveredSession,
    historyOnly: historyOnly,
    viewingInactiveBranch: viewingInactiveBranch,
  );
  final notice = switch (phase) {
    SessionUiPhase.failed => SessionNoticeKind.error,
    SessionUiPhase.recovery => SessionNoticeKind.recovery,
    SessionUiPhase.offline => SessionNoticeKind.offline,
    _ => null,
  };
  final isHistorical = historyOnly || viewingInactiveBranch;
  return SessionViewState(
    phase: phase,
    notice: notice,
    canCompose:
        canSend &&
        !commandInFlight &&
        (phase == SessionUiPhase.ready || phase == SessionUiPhase.running),
    // ChatController routes abort through the same live-command guard as
    // prompt. Keep the affordance in lock-step with that guard so a
    // read-only, stale, or disconnected session never exposes a no-op stop
    // button.
    canAbort: canSend && phase == SessionUiPhase.running && !commandInFlight,
    canRefresh: canRefresh,
    isHistorical: isHistorical,
  );
}

SessionUiPhase _resolvePhase({
  required RuntimeState runtimeState,
  required EventConnectionState eventConnectionState,
  required bool isSynchronizing,
  required TsPhoneProblem? problem,
  required bool recoveredSession,
  required bool historyOnly,
  required bool viewingInactiveBranch,
}) {
  // Error and recovery always outrank ordinary connection state.  This keeps
  // the page from showing a misleading "ready" or "reconnecting" affordance
  // while the user still has an unresolved failure.
  if (problem != null) return SessionUiPhase.failed;
  // Recovery is a live runtime condition. A page-open recovery marker is only
  // historical metadata, so it must not keep a successfully recovered session
  // blocked after the bridge reports idle/running.
  final runtimeRecovery = runtimeState == RuntimeState.recoveryRequired;
  // Keep the route-level marker in the decision for API compatibility, but
  // never let it promote an already recovered idle/running session.  The
  // second term is intentionally equivalent to the live-state check.
  if (runtimeRecovery) {
    return SessionUiPhase.recovery;
  }
  if (historyOnly || viewingInactiveBranch) return SessionUiPhase.history;
  if (runtimeState == RuntimeState.offline) return SessionUiPhase.offline;
  if (isSynchronizing || runtimeState == RuntimeState.connecting) {
    return SessionUiPhase.synchronizing;
  }
  if (runtimeState == RuntimeState.running) return SessionUiPhase.running;
  if (eventConnectionState != EventConnectionState.connected) {
    return SessionUiPhase.reconnecting;
  }
  return SessionUiPhase.ready;
}
