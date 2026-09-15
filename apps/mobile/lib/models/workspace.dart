enum RuntimeState {
  offline,
  connecting,
  idle,
  running,
  recoveryRequired;

  static RuntimeState parse(Object? value) => switch (value) {
    'offline' => RuntimeState.offline,
    'connecting' => RuntimeState.connecting,
    'idle' => RuntimeState.idle,
    'running' => RuntimeState.running,
    'recovery_required' => RuntimeState.recoveryRequired,
    _ => throw FormatException('Unknown runtime state: $value'),
  };

  bool get isAvailable =>
      this == RuntimeState.idle || this == RuntimeState.running;
}

/// Presentation metadata for the single App Server selected in settings.
class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.runtimeState,
    required this.isStreaming,
    required this.liveSessionCount,
    required this.sessionCount,
    this.updatedAt,
  });

  final String id;
  final String name;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final int liveSessionCount;
  final int sessionCount;
  final DateTime? updatedAt;
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

class SessionRuntimeModel {
  const SessionRuntimeModel({required this.provider, required this.id});

  factory SessionRuntimeModel.fromJson(Map<String, Object?> json) {
    final provider = json['provider'];
    final id = json['id'];
    if (provider is! String ||
        provider.isEmpty ||
        id is! String ||
        id.isEmpty) {
      throw const FormatException('Session runtime model is invalid');
    }
    return SessionRuntimeModel(provider: provider, id: id);
  }

  final String provider;
  final String id;

  String? get knownId => _knownModelValue(id);
  String? get knownProvider => _knownModelValue(provider);
}

class SessionContextUsage {
  const SessionContextUsage({
    required this.usedTokens,
    required this.limitTokens,
  });

  factory SessionContextUsage.fromJson(Map<String, Object?> json) {
    final usedTokens = json['usedTokens'];
    final limitTokens = json['limitTokens'];
    if (!json.containsKey('usedTokens') ||
        (usedTokens != null && (usedTokens is! int || usedTokens < 0)) ||
        limitTokens is! int ||
        limitTokens <= 0 ||
        json['measurement'] != 'pi_estimate') {
      throw const FormatException('Session context usage is invalid');
    }
    return SessionContextUsage(
      usedTokens: usedTokens as int?,
      limitTokens: limitTokens,
    );
  }

  final int? usedTokens;
  final int limitTokens;

  double? get percent =>
      usedTokens == null ? null : usedTokens! / limitTokens * 100;

  int? get remainingTokens {
    final used = usedTokens;
    if (used == null) return null;
    final remaining = limitTokens - used;
    return remaining < 0 ? 0 : remaining;
  }
}

class SessionRuntimeSnapshot {
  const SessionRuntimeSnapshot({
    required this.model,
    required this.updatedAt,
    this.context,
  });

  factory SessionRuntimeSnapshot.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 'ts-phone-session-runtime/1') {
      throw const FormatException('Session runtime schema is unsupported');
    }
    final rawModel = json['model'];
    final rawContext = json['context'];
    final rawUpdatedAt = json['updatedAt'];
    if (rawModel is! Map ||
        (rawContext != null && rawContext is! Map) ||
        rawUpdatedAt is! String) {
      throw const FormatException('Session runtime response is invalid');
    }
    final updatedAt = DateTime.tryParse(rawUpdatedAt);
    if (updatedAt == null) {
      throw const FormatException('Session runtime timestamp is invalid');
    }
    return SessionRuntimeSnapshot(
      model: SessionRuntimeModel.fromJson(Map<String, Object?>.from(rawModel)),
      context: rawContext == null
          ? null
          : SessionContextUsage.fromJson(
              Map<String, Object?>.from(rawContext as Map),
            ),
      updatedAt: updatedAt,
    );
  }

  final SessionRuntimeModel model;
  final SessionContextUsage? context;
  final DateTime updatedAt;
}

/// A Pi App Server session as projected for the mobile presentation.
class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.sessionRevision,
    required this.runtimeState,
    required this.isStreaming,
    this.accessMode = SessionAccessMode.controller,
    this.sessionName,
    this.model,
    this.promptProblem,
    this.runtime,
    this.activeAgentRunId,
    this.historyAvailable = false,
    this.historyOnly = false,
    this.canPrompt = true,
    this.capabilities = const <String>{},
    this.updatedAt,
  }) : assert(!historyOnly || historyAvailable);

  final String sessionId;
  final String sessionRevision;
  final String? sessionName;
  final String? model;
  final String? promptProblem;
  final SessionRuntimeSnapshot? runtime;
  final String? activeAgentRunId;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final SessionAccessMode accessMode;
  final bool historyAvailable;
  final bool historyOnly;
  final bool canPrompt;
  final Set<String> capabilities;
  final DateTime? updatedAt;

  bool hasCapability(String capability) => capabilities.contains(capability);

  String? get displayModel => runtime?.model.knownId ?? _knownModelValue(model);

  String? get modelRef {
    final configured = _knownModelValue(model);
    if (configured != null) return configured;
    final provider = runtime?.model.knownProvider;
    final id = runtime?.model.knownId;
    return provider != null && id != null ? '$provider/$id' : null;
  }

  String get shortId =>
      sessionId.substring(0, sessionId.length < 8 ? sessionId.length : 8);
}

String? _knownModelValue(String? value) {
  final text = value?.trim();
  return text == null ||
          text.isEmpty ||
          text.toLowerCase().split('/').contains('unknown')
      ? null
      : text;
}
