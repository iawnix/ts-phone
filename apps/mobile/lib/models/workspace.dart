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

enum LifecycleState {
  active,
  archived,
  trashed;

  static LifecycleState parse(Object? value) => switch (value) {
    'active' => LifecycleState.active,
    'archived' => LifecycleState.archived,
    'trashed' => LifecycleState.trashed,
    _ => throw FormatException('Unknown lifecycle state: $value'),
  };

  String get wireName => name;
}

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.runtimeState,
    required this.isStreaming,
    required this.liveSessionCount,
    required this.sessionCount,
    this.lifecycleState = LifecycleState.active,
    this.managementRevision = 'unmanaged',
    this.managed = false,
    this.updatedAt,
    this.deletedAt,
  });

  factory WorkspaceSummary.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final isStreaming = json['isStreaming'];
    final liveSessionCount = json['liveSessionCount'];
    final sessionCount = json['sessionCount'];
    final rawLifecycleState = json['lifecycleState'];
    final managementRevision = json['managementRevision'];
    final managed = json['managed'];
    if (id is! String ||
        name is! String ||
        isStreaming is! bool ||
        liveSessionCount is! int ||
        sessionCount is! int ||
        (rawLifecycleState != null && rawLifecycleState is! String) ||
        (managementRevision != null && managementRevision is! String) ||
        (managed != null && managed is! bool)) {
      throw const FormatException('Workspace response is invalid');
    }
    return WorkspaceSummary(
      id: id,
      name: name,
      runtimeState: RuntimeState.parse(json['runtimeState']),
      isStreaming: isStreaming,
      liveSessionCount: liveSessionCount,
      sessionCount: sessionCount,
      lifecycleState: rawLifecycleState == null
          ? LifecycleState.active
          : LifecycleState.parse(rawLifecycleState),
      managementRevision: managementRevision as String? ?? 'unmanaged',
      managed: managed as bool? ?? false,
      updatedAt: _optionalDateTime(json['updatedAt'], 'workspace updatedAt'),
      deletedAt: _optionalDateTime(json['deletedAt'], 'workspace deletedAt'),
    );
  }

  final String id;
  final String name;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final int liveSessionCount;
  final int sessionCount;
  final LifecycleState lifecycleState;
  final String managementRevision;
  final bool managed;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
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
    this.activeAgentRunId,
    this.historyAvailable = false,
    this.historyOnly = false,
    this.canPrompt = true,
    this.capabilities = const <String>{},
    this.lifecycleState = LifecycleState.active,
    this.managementRevision = 'unmanaged',
    this.managed = false,
    this.canActivate = false,
    this.updatedAt,
    this.deletedAt,
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
    final activeAgentRunId = json['activeAgentRunId'];
    final rawLifecycleState = json['lifecycleState'];
    final managementRevision = json['managementRevision'];
    final managed = json['managed'];
    final canActivate = json['canActivate'];
    if (sessionId is! String ||
        sessionRevision is! String ||
        isStreaming is! bool ||
        (historyAvailable != null && historyAvailable is! bool) ||
        (historyOnly != null && historyOnly is! bool) ||
        (canPrompt != null && canPrompt is! bool) ||
        (rawRuntime != null && rawRuntime is! Map) ||
        (rawLifecycleState != null && rawLifecycleState is! String) ||
        (managementRevision != null && managementRevision is! String) ||
        (managed != null && managed is! bool) ||
        (canActivate != null && canActivate is! bool) ||
        !json.containsKey('activeAgentRunId') ||
        (activeAgentRunId != null &&
            (activeAgentRunId is! String ||
                !RegExp(
                  r'^[A-Za-z0-9._:-]{1,160}$',
                ).hasMatch(activeAgentRunId))) ||
        (rawCapabilities != null &&
            (rawCapabilities is! List ||
                rawCapabilities.any((value) => value is! String)))) {
      throw const FormatException('Session response is invalid');
    }
    final runtimeState = RuntimeState.parse(json['runtimeState']);
    if ((runtimeState == RuntimeState.running) !=
        (activeAgentRunId is String && activeAgentRunId.isNotEmpty)) {
      throw const FormatException('Session agent run identity is invalid');
    }
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
      activeAgentRunId: activeAgentRunId as String?,
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
      lifecycleState: rawLifecycleState == null
          ? LifecycleState.active
          : LifecycleState.parse(rawLifecycleState),
      managementRevision: managementRevision as String? ?? 'unmanaged',
      managed: managed as bool? ?? false,
      canActivate: canActivate as bool? ?? false,
      updatedAt: _optionalDateTime(json['updatedAt'], 'session updatedAt'),
      deletedAt: _optionalDateTime(json['deletedAt'], 'session deletedAt'),
    );
  }

  final String sessionId;
  final String sessionRevision;
  final String? sessionName;
  final String? model;
  final SessionRuntimeSnapshot? runtime;
  final String? activeAgentRunId;
  final RuntimeState runtimeState;
  final bool isStreaming;
  final SessionAccessMode accessMode;
  final bool historyAvailable;
  final bool historyOnly;
  final bool canPrompt;
  final Set<String> capabilities;
  final LifecycleState lifecycleState;
  final String managementRevision;
  final bool managed;
  final bool canActivate;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

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

class WorkspaceCreationResult {
  const WorkspaceCreationResult({
    required this.workspace,
    required this.session,
  });

  factory WorkspaceCreationResult.fromJson(Map<String, Object?> json) {
    final workspace = json['workspace'];
    final session = json['session'];
    if (workspace is! Map || session is! Map) {
      throw const FormatException('Workspace creation response is invalid');
    }
    return WorkspaceCreationResult(
      workspace: WorkspaceSummary.fromJson(
        Map<String, Object?>.from(workspace),
      ),
      session: SessionSummary.fromJson(Map<String, Object?>.from(session)),
    );
  }

  final WorkspaceSummary workspace;
  final SessionSummary session;
}

class WorkspaceDeletionPreflight {
  const WorkspaceDeletionPreflight({
    required this.workspaceId,
    required this.managementRevision,
    required this.activeWorkers,
    required this.remoteCalculations,
    required this.pendingApprovals,
    required this.unresolvedRemoteEffects,
    required this.canDelete,
  });

  factory WorkspaceDeletionPreflight.fromJson(Map<String, Object?> json) {
    final workspaceId = json['workspaceId'];
    final managementRevision = json['managementRevision'];
    final activeWorkers = json['activeWorkers'];
    final remoteCalculations = json['remoteCalculations'];
    final pendingApprovals = json['pendingApprovals'];
    final unresolvedRemoteEffects = json['unresolvedRemoteEffects'];
    final canDelete = json['canDelete'];
    if (workspaceId is! String ||
        managementRevision is! String ||
        !_isCount(activeWorkers) ||
        !_isCount(remoteCalculations) ||
        !_isCount(pendingApprovals) ||
        !_isCount(unresolvedRemoteEffects) ||
        canDelete is! bool) {
      throw const FormatException('Workspace deletion preflight is invalid');
    }
    return WorkspaceDeletionPreflight(
      workspaceId: workspaceId,
      managementRevision: managementRevision,
      activeWorkers: activeWorkers as int,
      remoteCalculations: remoteCalculations as int,
      pendingApprovals: pendingApprovals as int,
      unresolvedRemoteEffects: unresolvedRemoteEffects as int,
      canDelete: canDelete,
    );
  }

  final String workspaceId;
  final String managementRevision;
  final int activeWorkers;
  final int remoteCalculations;
  final int pendingApprovals;
  final int unresolvedRemoteEffects;
  final bool canDelete;
}

DateTime? _optionalDateTime(Object? value, String label) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$label is invalid');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$label is invalid');
  return parsed;
}

bool _isCount(Object? value) => value is int && value >= 0;

String? _knownModelValue(String? value) {
  final text = value?.trim();
  return text == null ||
          text.isEmpty ||
          text.toLowerCase().split('/').contains('unknown')
      ? null
      : text;
}
