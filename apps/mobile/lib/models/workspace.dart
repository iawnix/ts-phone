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
      usedTokens == null ? null : (usedTokens! / limitTokens * 100);

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

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.sessionRevision,
    required this.runtimeState,
    required this.isStreaming,
    required this.accessMode,
    this.sessionName,
    this.model,
    this.runtime,
    this.historyAvailable = false,
    this.historyOnly = false,
    this.canPrompt = true,
    this.capabilities = const <String>{},
  }) : assert(!historyOnly || historyAvailable);

  factory SessionSummary.fromJson(Map<String, Object?> json) {
    final sessionId = json['sessionId'];
    final sessionRevision = json['sessionRevision'];
    final isStreaming = json['isStreaming'];
    final historyAvailable = json['historyAvailable'];
    final historyOnly = json['historyOnly'];
    final canPrompt = json['canPrompt'];
    final rawCapabilities = json['capabilities'];
    final rawRuntime = json['runtime'];
    if (sessionId is! String ||
        sessionRevision is! String ||
        isStreaming is! bool ||
        (historyAvailable != null && historyAvailable is! bool) ||
        (historyOnly != null && historyOnly is! bool) ||
        (canPrompt != null && canPrompt is! bool) ||
        (rawRuntime != null && rawRuntime is! Map) ||
        (rawCapabilities != null &&
            (rawCapabilities is! List ||
                rawCapabilities.any((value) => value is! String)))) {
      throw const FormatException('Session response is invalid');
    }
    final runtimeState = RuntimeState.parse(json['runtimeState']);
    final hasHistory = historyAvailable == true;
    final promptAvailable = canPrompt is bool
        ? canPrompt
        : runtimeState.isAvailable;
    final parsedCapabilities = rawCapabilities == null
        ? const <String>{}
        : Set<String>.unmodifiable((rawCapabilities as List).cast<String>());
    return SessionSummary(
      sessionId: sessionId,
      sessionRevision: sessionRevision,
      sessionName: json['sessionName'] as String?,
      model: json['model'] as String?,
      runtime: rawRuntime == null
          ? null
          : SessionRuntimeSnapshot.fromJson(
              Map<String, Object?>.from(rawRuntime as Map),
            ),
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
      capabilities: parsedCapabilities,
    );
  }

  final String sessionId;
  final String sessionRevision;
  final String? sessionName;
  final String? model;
  final SessionRuntimeSnapshot? runtime;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final SessionAccessMode accessMode;
  final bool historyAvailable;
  final bool historyOnly;
  final bool canPrompt;
  final Set<String> capabilities;

  bool hasCapability(String capability) => capabilities.contains(capability);

  String? get displayModel => runtime?.model.id ?? model;

  String get shortId =>
      sessionId.substring(0, sessionId.length < 8 ? sessionId.length : 8);
}
