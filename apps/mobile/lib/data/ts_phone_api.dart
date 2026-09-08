import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/connection_settings.dart';
import '../models/session_timeline.dart';
import '../models/workspace.dart';
import 'sse_parser.dart';

class TsPhoneApiException implements Exception {
  const TsPhoneApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

enum TsPhoneProblemKind { authentication, incompatible, unavailable, request }

enum TsPhoneProblemCode {
  incompatible,
  authentication,
  sessionOffline,
  sessionChanged,
  serviceUnavailable,
  connectionFailed,
  requestTimeout,
  requestFailed,
  networkRetrying,
  invalidMessage,
  invalidApproval,
  invalidHistoryMessage,
  approvalExpired,
  approvalStale,
  approvalMissing,
  agentRunChanged,
  managementChanged,
  resourcesBusy,
  preflightUnavailable,
  managementCapacity,
  managementUnsupported,
  modelUnavailable,
  modelAuthMissing,
  modelCheckFailed,
  promptRejected,
  runtimeExtensionError,
  deliveryUncertain,
  activationExternalOwner,
  activationUpgradeRequired,
  activationWriterActive,
  activationInspectionFailed,
  activationGuardInvalid,
  activationFailed,
  activationOutcomeUnknown,
  activationCapacity,
  runtimeRecoveryRequired,
}

class TsPhoneProblem {
  const TsPhoneProblem(this.kind, this.code);

  final TsPhoneProblemKind kind;
  final TsPhoneProblemCode code;
}

TsPhoneProblem describeTsPhoneProblem(Object error) {
  if (error is TimeoutException) {
    return const TsPhoneProblem(
      TsPhoneProblemKind.unavailable,
      TsPhoneProblemCode.requestTimeout,
    );
  }
  if (error is FormatException) {
    return const TsPhoneProblem(
      TsPhoneProblemKind.incompatible,
      TsPhoneProblemCode.incompatible,
    );
  }
  if (error is TsPhoneApiException) {
    final promptCode = switch (error.code) {
      'model_unavailable' => TsPhoneProblemCode.modelUnavailable,
      'model_auth_missing' => TsPhoneProblemCode.modelAuthMissing,
      'model_check_failed' => TsPhoneProblemCode.modelCheckFailed,
      'prompt_rejected' => TsPhoneProblemCode.promptRejected,
      'runtime_extension_error' => TsPhoneProblemCode.runtimeExtensionError,
      'command_ambiguous' ||
      'bridge_disconnected' => TsPhoneProblemCode.deliveryUncertain,
      _ => null,
    };
    if (promptCode != null) {
      return TsPhoneProblem(TsPhoneProblemKind.request, promptCode);
    }
    if (error.code == 'management_unsupported') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.incompatible,
        TsPhoneProblemCode.managementUnsupported,
      );
    }
    final managementCode = switch (error.code) {
      'workspace_management_changed' ||
      'session_management_changed' => TsPhoneProblemCode.managementChanged,
      'session_switch_required' ||
      'session_switch_stale' => TsPhoneProblemCode.managementChanged,
      'external_controller' => TsPhoneProblemCode.activationExternalOwner,
      'session_guard_upgrade_required' || 'session_writer_unverified' =>
        TsPhoneProblemCode.activationUpgradeRequired,
      'session_writer_active' => TsPhoneProblemCode.activationWriterActive,
      'session_writer_inspection_failed' =>
        TsPhoneProblemCode.activationInspectionFailed,
      'session_guard_invalid' => TsPhoneProblemCode.activationGuardInvalid,
      'worker_start_failed' ||
      'worker_start_timeout' ||
      'worker_start_interrupted' => TsPhoneProblemCode.activationFailed,
      'activation_outcome_unknown' =>
        TsPhoneProblemCode.activationOutcomeUnknown,
      'worker_cleanup_uncertain' ||
      'session_recovery_required' => TsPhoneProblemCode.runtimeRecoveryRequired,
      'activation_capacity_exceeded' => TsPhoneProblemCode.activationCapacity,
      'activation_id_conflict' => TsPhoneProblemCode.managementChanged,
      'workspace_delete_blocked' ||
      'workspace_has_active_workers' ||
      'controller_session_active' ||
      'workspace_activating' ||
      'session_not_ready' ||
      'worker_identity_conflict' ||
      'session_active' ||
      'session_has_pending_approvals' => TsPhoneProblemCode.resourcesBusy,
      'workspace_preflight_unavailable' ||
      'worker_unavailable' => TsPhoneProblemCode.preflightUnavailable,
      'management_capacity_exceeded' => TsPhoneProblemCode.managementCapacity,
      _ => null,
    };
    if (managementCode != null) {
      return TsPhoneProblem(TsPhoneProblemKind.request, managementCode);
    }
    if (error.statusCode == 401 || error.statusCode == 403) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.authentication,
        TsPhoneProblemCode.authentication,
      );
    }
    if (error.code == 'session_offline') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.sessionOffline,
      );
    }
    if (error.code == 'session_resync_required') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.sessionChanged,
      );
    }
    if (error.code == 'approval_expired') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalExpired,
      );
    }
    if (error.code == 'approval_stale') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalStale,
      );
    }
    if (error.code == 'approval_not_found') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalMissing,
      );
    }
    if (error.code == 'agent_run_stale' || error.code == 'agent_not_running') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.agentRunChanged,
      );
    }
    if (error.code == 'request_timeout') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.requestTimeout,
      );
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.serviceUnavailable,
      );
    }
    return const TsPhoneProblem(
      TsPhoneProblemKind.request,
      TsPhoneProblemCode.requestFailed,
    );
  }
  return const TsPhoneProblem(
    TsPhoneProblemKind.unavailable,
    TsPhoneProblemCode.connectionFailed,
  );
}

class TsPhoneEvent {
  const TsPhoneEvent({
    required this.id,
    required this.workspaceId,
    required this.sessionId,
    required this.sessionRevision,
    required this.instanceEpoch,
    required this.sessionGeneration,
    required this.type,
    required this.payload,
    required this.at,
  });

  factory TsPhoneEvent.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Event must be an object');
    final json = value.cast<String, Object?>();
    if (json['protocolVersion'] != 'ts-phone-events/3' ||
        json['id'] is! String ||
        json['workspaceId'] is! String ||
        json['sessionId'] is! String ||
        json['sessionRevision'] is! String ||
        json['type'] is! String ||
        json['at'] is! String) {
      throw const FormatException('Event envelope is invalid');
    }
    return TsPhoneEvent(
      id: json['id']! as String,
      workspaceId: json['workspaceId']! as String,
      sessionId: json['sessionId']! as String,
      sessionRevision: json['sessionRevision']! as String,
      instanceEpoch: json['instanceEpoch'] as String?,
      sessionGeneration: json['sessionGeneration'] as int?,
      type: json['type']! as String,
      payload: json['payload'],
      at: DateTime.parse(json['at']! as String),
    );
  }

  final String id;
  final String workspaceId;
  final String sessionId;
  final String sessionRevision;
  final String? instanceEpoch;
  final int? sessionGeneration;
  final String type;
  final Object? payload;
  final DateTime at;
}

class TsPhoneMessageSnapshot {
  const TsPhoneMessageSnapshot({
    required this.sessionId,
    required this.sessionRevision,
    required this.messages,
    required this.lastEventId,
    this.activeAgentRunId,
    this.messageIds,
    this.hasMore = false,
    this.nextBefore,
    this.hasLater = false,
    this.nextAfter,
  });

  final String sessionId;
  final String sessionRevision;
  final List<Object?> messages;
  final String lastEventId;
  final String? activeAgentRunId;
  final List<String>? messageIds;
  final bool hasMore;
  final String? nextBefore;
  final bool hasLater;
  final String? nextAfter;
}

class TsPhoneTimelineSnapshot {
  const TsPhoneTimelineSnapshot({
    required this.sessionId,
    required this.sessionRevision,
    required this.items,
    required this.history,
    required this.hasMore,
    required this.lastEventId,
    required this.capabilities,
    this.activeAgentRunId,
    this.nextBefore,
    this.hasLater = false,
    this.nextAfter,
  });

  final String sessionId;
  final String sessionRevision;
  final List<SessionTimelineItem> items;
  final TimelineHistorySummary history;
  final bool hasMore;
  final String? nextBefore;
  final bool hasLater;
  final String? nextAfter;
  final String lastEventId;
  final Set<String> capabilities;
  final String? activeAgentRunId;
}

abstract interface class TsPhoneHistoryGateway {
  Future<TsPhoneMessageSnapshot> getMessageWindow(
    String workspaceId,
    String sessionId, {
    String? after,
    bool fromStart = false,
    required int limit,
  });
  Future<TsPhoneTimelineSnapshot> getTimelineWindow(
    String workspaceId,
    String sessionId, {
    String? after,
    bool fromStart = false,
    String? branch,
    required int limit,
  });
}

abstract interface class TsPhoneGateway {
  Future<Map<String, Object?>> version();
  Future<List<WorkspaceSummary>> listWorkspaces();
  Future<List<SessionSummary>> listSessions(String workspaceId);
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  });
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  });
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  });
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  });
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  });
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  });
  void close();
}

abstract interface class TsPhoneManagementGateway {
  Future<List<WorkspaceSummary>> listWorkspacesByLifecycle(
    LifecycleState lifecycleState,
  );
  Future<WorkspaceCreationResult> createWorkspace(String name);
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String managementRevision,
    String name,
  );
  Future<WorkspaceSummary> archiveWorkspace(
    String workspaceId,
    String managementRevision,
  );
  Future<WorkspaceSummary> restoreWorkspace(
    String workspaceId,
    String managementRevision,
  );
  Future<WorkspaceSummary> trashWorkspace(
    String workspaceId,
    String managementRevision,
  );
  Future<void> purgeWorkspace(String workspaceId, String managementRevision);
  Future<WorkspaceDeletionPreflight> workspaceDeletionPreflight(
    String workspaceId,
  );
  Future<List<SessionSummary>> listSessionsByLifecycle(
    String workspaceId,
    LifecycleState lifecycleState,
  );
  Future<SessionSummary> createSession(
    String workspaceId, {
    required SessionAccessMode accessMode,
    String? name,
    String? model,
  });
  Future<SessionSummary> renameSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
    String name,
  );
  Future<SessionSummary> archiveSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  );
  Future<SessionSummary> restoreSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  );
  Future<SessionSummary> trashSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  );
  Future<void> purgeSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  );
  Future<SessionSummary> activateSession(
    String workspaceId,
    String sessionId,
    String managementRevision, {
    SessionAccessMode? accessMode,
    String? requestId,
    SessionActivationConflict? switchFrom,
  });
}

class TsPhoneApi
    implements TsPhoneGateway, TsPhoneManagementGateway, TsPhoneHistoryGateway {
  TsPhoneApi(
    this.settings, {
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
    this.activationTimeout = const Duration(seconds: 90),
  }) : assert(!requestTimeout.isNegative && requestTimeout != Duration.zero),
       assert(
         !activationTimeout.isNegative && activationTimeout != Duration.zero,
       ),
       _client = client ?? http.Client();

  final ConnectionSettings settings;
  final http.Client _client;
  final Duration requestTimeout;
  final Duration activationTimeout;

  Map<String, String> get _authorization => <String, String>{
    'Authorization': 'Bearer ${settings.token}',
  };

  @override
  Future<Map<String, Object?>> version() async {
    final data = await _request('GET', 'version');
    return _asMap(data, 'Version response');
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return listWorkspacesByLifecycle(LifecycleState.active);
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspacesByLifecycle(
    LifecycleState lifecycleState,
  ) async {
    final data = await _request(
      'GET',
      'workspaces',
      queryParameters: <String, String>{'state': lifecycleState.wireName},
    );
    if (data is! List) throw const FormatException('Workspace list is invalid');
    return data
        .map((value) => WorkspaceSummary.fromJson(_asMap(value, 'Workspace')))
        .toList(growable: false);
  }

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    return listSessionsByLifecycle(workspaceId, LifecycleState.active);
  }

  @override
  Future<List<SessionSummary>> listSessionsByLifecycle(
    String workspaceId,
    LifecycleState lifecycleState,
  ) async {
    final data = await _request(
      'GET',
      _workspacePath(workspaceId, 'sessions'),
      queryParameters: <String, String>{'state': lifecycleState.wireName},
    );
    if (data is! List) throw const FormatException('Session list is invalid');
    return data
        .map((value) => SessionSummary.fromJson(_asMap(value, 'Session')))
        .toList(growable: false);
  }

  @override
  Future<WorkspaceCreationResult> createWorkspace(String name) async {
    final value = await _request('POST', 'workspaces', body: {'name': name});
    return WorkspaceCreationResult.fromJson(
      _asMap(value, 'Workspace creation'),
    );
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String managementRevision,
    String name,
  ) => _workspaceMutation(
    workspaceId,
    '',
    method: 'PATCH',
    body: {'name': name, 'managementRevision': managementRevision},
  );

  @override
  Future<WorkspaceSummary> archiveWorkspace(
    String workspaceId,
    String managementRevision,
  ) => _workspaceLifecycle(workspaceId, 'archive', managementRevision);

  @override
  Future<WorkspaceSummary> restoreWorkspace(
    String workspaceId,
    String managementRevision,
  ) => _workspaceLifecycle(workspaceId, 'restore', managementRevision);

  @override
  Future<WorkspaceSummary> trashWorkspace(
    String workspaceId,
    String managementRevision,
  ) => _workspaceLifecycle(workspaceId, 'trash', managementRevision);

  @override
  Future<void> purgeWorkspace(
    String workspaceId,
    String managementRevision,
  ) async {
    await _request(
      'POST',
      _workspacePath(workspaceId, 'purge'),
      body: {
        'managementRevision': managementRevision,
        'confirmation': workspaceId,
      },
    );
  }

  @override
  Future<WorkspaceDeletionPreflight> workspaceDeletionPreflight(
    String workspaceId,
  ) async {
    final value = await _request(
      'GET',
      _workspacePath(workspaceId, 'deletion-preflight'),
    );
    return WorkspaceDeletionPreflight.fromJson(
      _asMap(value, 'Workspace deletion preflight'),
    );
  }

  @override
  Future<SessionSummary> createSession(
    String workspaceId, {
    required SessionAccessMode accessMode,
    String? name,
    String? model,
  }) async {
    final value = await _request(
      'POST',
      _workspacePath(workspaceId, 'sessions'),
      body: {'accessMode': accessMode.name, 'name': ?name, 'model': ?model},
    );
    return SessionSummary.fromJson(_asMap(value, 'Session creation'));
  }

  @override
  Future<SessionSummary> renameSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
    String name,
  ) => _sessionMutation(
    workspaceId,
    sessionId,
    '',
    method: 'PATCH',
    body: {'name': name, 'managementRevision': managementRevision},
  );

  @override
  Future<SessionSummary> archiveSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) => _sessionLifecycle(workspaceId, sessionId, 'archive', managementRevision);

  @override
  Future<SessionSummary> restoreSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) => _sessionLifecycle(workspaceId, sessionId, 'restore', managementRevision);

  @override
  Future<SessionSummary> trashSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) => _sessionLifecycle(workspaceId, sessionId, 'trash', managementRevision);

  @override
  Future<void> purgeSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
  ) async {
    await _request(
      'POST',
      _sessionPath(workspaceId, sessionId, 'purge'),
      body: {
        'managementRevision': managementRevision,
        'confirmation': sessionId,
      },
    );
  }

  @override
  Future<SessionSummary> activateSession(
    String workspaceId,
    String sessionId,
    String managementRevision, {
    SessionAccessMode? accessMode,
    String? requestId,
    SessionActivationConflict? switchFrom,
  }) async {
    try {
      return await _sessionMutation(
        workspaceId,
        sessionId,
        'activate',
        timeout: activationTimeout,
        body: {
          'managementRevision': managementRevision,
          if (accessMode != null) 'accessMode': accessMode.name,
          'requestId': ?requestId,
          if (switchFrom != null) 'switchFrom': switchFrom.confirmation,
        },
      );
    } on Object catch (error) {
      if (error is http.ClientException ||
          (error is TsPhoneApiException && error.code == 'request_timeout')) {
        throw const TsPhoneApiException(
          'Activation outcome is unknown; refresh before continuing',
          code: 'activation_outcome_unknown',
        );
      }
      rethrow;
    }
  }

  Future<WorkspaceSummary> _workspaceLifecycle(
    String workspaceId,
    String action,
    String managementRevision,
  ) => _workspaceMutation(
    workspaceId,
    action,
    body: {'managementRevision': managementRevision},
  );

  Future<WorkspaceSummary> _workspaceMutation(
    String workspaceId,
    String resource, {
    String method = 'POST',
    required Map<String, Object?> body,
  }) async {
    final path = resource.isEmpty
        ? 'workspaces/${Uri.encodeComponent(workspaceId)}'
        : _workspacePath(workspaceId, resource);
    final value = await _request(method, path, body: body);
    return WorkspaceSummary.fromJson(_asMap(value, 'Workspace mutation'));
  }

  Future<SessionSummary> _sessionLifecycle(
    String workspaceId,
    String sessionId,
    String action,
    String managementRevision,
  ) => _sessionMutation(
    workspaceId,
    sessionId,
    action,
    body: {'managementRevision': managementRevision},
  );

  Future<SessionSummary> _sessionMutation(
    String workspaceId,
    String sessionId,
    String resource, {
    String method = 'POST',
    Duration? timeout,
    required Map<String, Object?> body,
  }) async {
    final path = resource.isEmpty
        ? '${_workspacePath(workspaceId, 'sessions')}/${Uri.encodeComponent(sessionId)}'
        : _sessionPath(workspaceId, sessionId, resource);
    final value = await _request(method, path, body: body, timeout: timeout);
    return SessionSummary.fromJson(_asMap(value, 'Session mutation'));
  }

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    String? after,
    bool fromStart = false,
    int? limit,
  }) async {
    if (limit != null && (limit < 1 || limit > 500)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final data = _asMap(
      await _request(
        'GET',
        _sessionPath(workspaceId, sessionId, 'messages'),
        queryParameters: <String, String>{
          'before': ?before,
          'after': ?after,
          if (fromStart) 'edge': 'start',
          if (limit != null) 'limit': '$limit',
        },
      ),
      'Messages response',
    );
    final messages = data['messages'];
    final rawMessageIds = data['messageIds'];
    final rawHasMore = data['hasMore'];
    final rawNextBefore = data['nextBefore'];
    final lastEventId = data['lastEventId'];
    final responseSessionId = data['sessionId'];
    final sessionRevision = data['sessionRevision'];
    final activeAgentRunId = data['activeAgentRunId'];
    if (messages is! List ||
        lastEventId is! String ||
        lastEventId.isEmpty ||
        responseSessionId is! String ||
        responseSessionId != sessionId ||
        sessionRevision is! String ||
        !data.containsKey('activeAgentRunId') ||
        !_isOptionalBoundedId(activeAgentRunId)) {
      throw const FormatException('Messages response is invalid');
    }
    List<String>? messageIds;
    if (rawMessageIds != null) {
      if (rawMessageIds is! List ||
          rawMessageIds.length != messages.length ||
          rawMessageIds.any((value) => value is! String)) {
        throw const FormatException('Message ids are invalid');
      }
      messageIds = rawMessageIds.cast<String>();
      if (messageIds.toSet().length != messageIds.length ||
          messageIds.any((id) => !RegExp(r'^[0-9a-f]{8}$').hasMatch(id))) {
        throw const FormatException('Message ids are invalid or not unique');
      }
    }
    final hasMore = rawHasMore ?? false;
    if (hasMore is! bool ||
        (rawNextBefore != null && rawNextBefore is! String) ||
        (hasMore &&
            (messageIds == null ||
                messageIds.isEmpty ||
                rawNextBefore != messageIds.first)) ||
        (!hasMore && rawNextBefore != null)) {
      throw const FormatException('Message pagination is invalid');
    }
    final hasLater = _validateLaterCursor(data, messageIds ?? const []);
    return TsPhoneMessageSnapshot(
      sessionId: responseSessionId,
      sessionRevision: sessionRevision,
      messages: messages.cast<Object?>(),
      lastEventId: lastEventId,
      activeAgentRunId: activeAgentRunId as String?,
      messageIds: messageIds,
      hasMore: hasMore,
      nextBefore: rawNextBefore as String?,
      hasLater: hasLater,
      nextAfter: data['nextAfter'] as String?,
    );
  }

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    String? after,
    bool fromStart = false,
    int? limit,
    String? branch,
  }) async {
    if (limit != null && (limit < 1 || limit > 500)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final data = _asMap(
      await _request(
        'GET',
        _sessionPath(workspaceId, sessionId, 'timeline'),
        queryParameters: <String, String>{
          'before': ?before,
          'after': ?after,
          if (fromStart) 'edge': 'start',
          if (limit != null) 'limit': '$limit',
          'branch': ?branch,
        },
      ),
      'Timeline response',
    );
    if (data['schemaVersion'] != 'ts-phone-timeline/1' ||
        data['sessionId'] != sessionId ||
        data['sessionRevision'] is! String ||
        data['lastEventId'] is! String ||
        (data['lastEventId']! as String).isEmpty ||
        !data.containsKey('activeAgentRunId') ||
        !_isOptionalBoundedId(data['activeAgentRunId']) ||
        data['items'] is! List ||
        data['hasMore'] is! bool ||
        data['capabilities'] is! List ||
        (data['capabilities']! as List).any((value) => value is! String)) {
      throw const FormatException('Timeline response is invalid');
    }
    final items = (data['items']! as List)
        .map(SessionTimelineItem.fromJson)
        .toList(growable: false);
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Timeline item ids are not unique');
    }
    final hasMore = data['hasMore']! as bool;
    final nextBefore = data['nextBefore'];
    if ((nextBefore != null && nextBefore is! String) ||
        (hasMore && (items.isEmpty || nextBefore != items.first.id)) ||
        (!hasMore && nextBefore != null)) {
      throw const FormatException('Timeline pagination is invalid');
    }
    final history = TimelineHistorySummary.fromJson(data['history']);
    final hasLater = _validateLaterCursor(
      data,
      items.map((item) => item.id).toList(),
    );
    if (history.totalItems < items.length) {
      throw const FormatException('Timeline history totals are invalid');
    }
    return TsPhoneTimelineSnapshot(
      sessionId: sessionId,
      sessionRevision: data['sessionRevision']! as String,
      items: List<SessionTimelineItem>.unmodifiable(items),
      history: history,
      hasMore: hasMore,
      nextBefore: nextBefore as String?,
      hasLater: hasLater,
      nextAfter: data['nextAfter'] as String?,
      lastEventId: data['lastEventId']! as String,
      capabilities: Set<String>.unmodifiable(
        (data['capabilities']! as List).cast<String>(),
      ),
      activeAgentRunId: data['activeAgentRunId'] as String?,
    );
  }

  @override
  Future<TsPhoneMessageSnapshot> getMessageWindow(
    String workspaceId,
    String sessionId, {
    String? after,
    bool fromStart = false,
    required int limit,
  }) => getMessages(
    workspaceId,
    sessionId,
    after: after,
    fromStart: fromStart,
    limit: limit,
  );

  @override
  Future<TsPhoneTimelineSnapshot> getTimelineWindow(
    String workspaceId,
    String sessionId, {
    String? after,
    bool fromStart = false,
    String? branch,
    required int limit,
  }) => getTimeline(
    workspaceId,
    sessionId,
    after: after,
    fromStart: fromStart,
    branch: branch,
    limit: limit,
  );

  static bool _validateLaterCursor(
    Map<String, Object?> data,
    List<String> ids,
  ) {
    final hasLater = data['hasLater'] ?? false;
    final after = data['nextAfter'];
    if (hasLater is! bool ||
        (hasLater && (ids.isEmpty || after != ids.last)) ||
        (!hasLater && after != null)) {
      throw const FormatException('Forward history pagination is invalid');
    }
    return hasLater;
  }

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) async {
    final body = <String, Object?>{
      'clientMessageId': clientMessageId,
      'sessionRevision': sessionRevision,
      'message': message,
    };
    await _request(
      'POST',
      _sessionPath(workspaceId, sessionId, 'messages'),
      body: body,
    );
  }

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) async {
    await _request(
      'POST',
      _sessionPath(workspaceId, sessionId, 'abort'),
      body: <String, Object?>{
        'sessionRevision': sessionRevision,
        'agentRunId': agentRunId,
      },
    );
  }

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async {
    await _request(
      'POST',
      '${_sessionPath(workspaceId, sessionId, 'approvals')}/${Uri.encodeComponent(approvalId)}',
      body: <String, Object?>{
        'approved': approved,
        'sessionRevision': sessionRevision,
      },
    );
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) async* {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'GET',
            settings.endpoint(_sessionPath(workspaceId, sessionId, 'events')),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            ..._authorization,
            'Accept': 'text/event-stream',
          });
    if (lastEventId != null) request.headers['Last-Event-ID'] = lastEventId;
    late final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(requestTimeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const TsPhoneApiException(
        'Request timed out',
        code: 'request_timeout',
      );
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw _apiError(response.statusCode, body);
    }
    onConnected?.call();
    final parser = SseParser();
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final record = parser.addLine(line);
      if (record == null) continue;
      final event = TsPhoneEvent.fromJson(jsonDecode(record.data));
      if (record.id != null && record.id != event.id) {
        throw const FormatException('SSE id does not match its event envelope');
      }
      yield event;
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    Duration? timeout,
  }) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            method,
            settings
                .endpoint(path)
                .replace(
                  queryParameters: queryParameters?.isEmpty == true
                      ? null
                      : queryParameters,
                ),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(_authorization);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    late final http.Response response;
    try {
      response = await _client
          .send(request)
          .then((streamed) => http.Response.fromStream(streamed))
          .timeout(timeout ?? requestTimeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const TsPhoneApiException(
        'Request timed out',
        code: 'request_timeout',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _apiError(response.statusCode, response.body);
      final creatingManagedResource =
          method == 'POST' &&
          (path == 'workspaces' ||
              RegExp(r'^workspaces/[^/]+/sessions$').hasMatch(path));
      if (creatingManagedResource &&
          error.statusCode == 404 &&
          error.code == 'not_found') {
        throw const TsPhoneApiException(
          'The Phone Host does not support project and session creation. Upgrade the Host.',
          statusCode: 404,
          code: 'management_unsupported',
        );
      }
      throw error;
    }
    final payload = _asMap(jsonDecode(response.body), 'API response');
    if (payload['apiVersion'] != 'ts-phone-api/4') {
      throw const FormatException('Server API version is not supported');
    }
    return payload['data'];
  }

  TsPhoneApiException _apiError(int status, String body) {
    try {
      final payload = _asMap(jsonDecode(body), 'Error response');
      final error = _asMap(payload['error'], 'Error');
      return TsPhoneApiException(
        error['message'] is String
            ? error['message']! as String
            : 'Request failed',
        statusCode: status,
        code: error['code'] as String?,
      );
    } on Object {
      return TsPhoneApiException(
        'Server returned HTTP $status',
        statusCode: status,
      );
    }
  }

  String _workspacePath(String workspaceId, String resource) {
    return 'workspaces/${Uri.encodeComponent(workspaceId)}/$resource';
  }

  String _sessionPath(String workspaceId, String sessionId, String resource) {
    return '${_workspacePath(workspaceId, 'sessions')}/${Uri.encodeComponent(sessionId)}/$resource';
  }

  static Map<String, Object?> _asMap(Object? value, String label) {
    if (value is! Map) throw FormatException('$label is invalid');
    return value.cast<String, Object?>();
  }

  static bool _isOptionalBoundedId(Object? value) =>
      value == null ||
      (value is String && RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(value));

  @override
  void close() => _client.close();
}

String createTsPhoneClientMessageId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  final entropy = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return 'phone-$timestamp-$entropy';
}
