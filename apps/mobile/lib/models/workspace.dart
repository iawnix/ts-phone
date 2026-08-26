enum RuntimeState {
  offline,
  connecting,
  idle,
  running,
  recoveryRequired;

  static RuntimeState parse(Object? value) {
    return switch (value) {
      'offline' => RuntimeState.offline,
      'connecting' => RuntimeState.connecting,
      'idle' => RuntimeState.idle,
      'running' => RuntimeState.running,
      'recovery_required' => RuntimeState.recoveryRequired,
      _ => throw FormatException('Unknown runtime state: $value'),
    };
  }

  bool get isAvailable =>
      this == RuntimeState.idle || this == RuntimeState.running;
}

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.runtimeState,
    required this.isStreaming,
    required this.liveSessionCount,
    required this.sessionCount,
  });

  factory WorkspaceSummary.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final isStreaming = json['isStreaming'];
    final liveSessionCount = json['liveSessionCount'];
    final sessionCount = json['sessionCount'];
    if (id is! String ||
        name is! String ||
        isStreaming is! bool ||
        liveSessionCount is! int ||
        sessionCount is! int) {
      throw const FormatException('Workspace response is invalid');
    }
    return WorkspaceSummary(
      id: id,
      name: name,
      runtimeState: RuntimeState.parse(json['runtimeState']),
      isStreaming: isStreaming,
      liveSessionCount: liveSessionCount,
      sessionCount: sessionCount,
    );
  }

  final String id;
  final String name;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final int liveSessionCount;
  final int sessionCount;
}

enum SessionAccessMode {
  controller,
  observer;

  static SessionAccessMode parse(Object? value) => switch (value) {
    'controller' => SessionAccessMode.controller,
    'observer' => SessionAccessMode.observer,
    _ => throw FormatException('Unknown session access mode: $value'),
  };
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.sessionRevision,
    required this.runtimeState,
    required this.isStreaming,
    required this.accessMode,
    this.sessionName,
    this.model,
    this.historyAvailable = false,
    this.historyOnly = false,
    this.canPrompt = true,
  }) : assert(!historyOnly || historyAvailable);

  factory SessionSummary.fromJson(Map<String, Object?> json) {
    final sessionId = json['sessionId'];
    final sessionRevision = json['sessionRevision'];
    final isStreaming = json['isStreaming'];
    final historyAvailable = json['historyAvailable'];
    final historyOnly = json['historyOnly'];
    final canPrompt = json['canPrompt'];
    if (sessionId is! String ||
        sessionRevision is! String ||
        isStreaming is! bool ||
        (historyAvailable != null && historyAvailable is! bool) ||
        (historyOnly != null && historyOnly is! bool) ||
        (canPrompt != null && canPrompt is! bool)) {
      throw const FormatException('Session response is invalid');
    }
    final runtimeState = RuntimeState.parse(json['runtimeState']);
    final hasHistory = historyAvailable == true;
    final promptAvailable = canPrompt is bool
        ? canPrompt
        : runtimeState.isAvailable;
    return SessionSummary(
      sessionId: sessionId,
      sessionRevision: sessionRevision,
      sessionName: json['sessionName'] as String?,
      model: json['model'] as String?,
      runtimeState: runtimeState,
      isStreaming: isStreaming,
      accessMode: SessionAccessMode.parse(json['accessMode']),
      historyAvailable: hasHistory,
      historyOnly:
          historyOnly == true ||
          (runtimeState == RuntimeState.offline &&
              hasHistory &&
              !promptAvailable),
      canPrompt: promptAvailable,
    );
  }

  final String sessionId;
  final String sessionRevision;
  final String? sessionName;
  final String? model;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final SessionAccessMode accessMode;
  final bool historyAvailable;
  final bool historyOnly;
  final bool canPrompt;

  String get shortId =>
      sessionId.substring(0, sessionId.length < 8 ? sessionId.length : 8);
}
