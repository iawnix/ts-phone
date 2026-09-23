import 'dart:async';
import 'dart:math';

import '../models/phone_model.dart';
import '../models/session_timeline.dart';
import '../models/workspace.dart';

class TsPhoneApiException implements Exception {
  const TsPhoneApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryable,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final bool? retryable;

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
  modelStorageUnavailable,
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
  apiRouteMissing,
  queueStorageUnavailable,
  queueCapacity,
  queueRecovery,
  providerUnavailable,
  providerRateLimited,
  providerAuthFailed,
  providerError,
  generationIncomplete,
}

class TsPhoneProblem {
  const TsPhoneProblem(this.kind, this.code);

  final TsPhoneProblemKind kind;
  final TsPhoneProblemCode code;
}

TsPhoneProblem describeTsPhoneProblem(Object error) {
  if (error is FormatException) {
    return const TsPhoneProblem(
      TsPhoneProblemKind.incompatible,
      TsPhoneProblemCode.incompatible,
    );
  }
  if (error is TimeoutException) {
    return const TsPhoneProblem(
      TsPhoneProblemKind.unavailable,
      TsPhoneProblemCode.requestTimeout,
    );
  }
  if (error is TsPhoneApiException) {
    final code = switch (error.code) {
      'authentication' || 'unauthorized' => TsPhoneProblemCode.authentication,
      'request_timeout' => TsPhoneProblemCode.requestTimeout,
      'session_offline' => TsPhoneProblemCode.sessionOffline,
      'workspace_busy' || 'session_busy' => TsPhoneProblemCode.resourcesBusy,
      'turn_mismatch' => TsPhoneProblemCode.agentRunChanged,
      'session_lifecycle_unavailable' =>
        TsPhoneProblemCode.managementUnsupported,
      'session_start_timeout' ||
      'request_uncertain' => TsPhoneProblemCode.deliveryUncertain,
      'service_unavailable' ||
      'connection_closed' => TsPhoneProblemCode.serviceUnavailable,
      'session_not_found' ||
      'workspace_not_found' => TsPhoneProblemCode.sessionChanged,
      'service_not_found' ||
      'service_member_not_found' ||
      'version' ||
      'protocol_mismatch' ||
      'method_not_found' => TsPhoneProblemCode.incompatible,
      'model_unavailable' => TsPhoneProblemCode.modelUnavailable,
      'model_auth_missing' => TsPhoneProblemCode.modelAuthMissing,
      'provider_unavailable' => TsPhoneProblemCode.providerUnavailable,
      'provider_rate_limited' => TsPhoneProblemCode.providerRateLimited,
      'provider_auth_failed' => TsPhoneProblemCode.providerAuthFailed,
      'provider_error' => TsPhoneProblemCode.providerError,
      'prompt_rejected' => TsPhoneProblemCode.promptRejected,
      'runtime_extension_error' => TsPhoneProblemCode.runtimeExtensionError,
      'generation_incomplete' => TsPhoneProblemCode.generationIncomplete,
      'approval_expired' => TsPhoneProblemCode.approvalExpired,
      'approval_stale' => TsPhoneProblemCode.approvalStale,
      'approval_missing' ||
      'approval_not_found' => TsPhoneProblemCode.approvalMissing,
      'agent_run_stale' ||
      'agent_not_running' => TsPhoneProblemCode.agentRunChanged,
      _ => TsPhoneProblemCode.requestFailed,
    };
    if (error.statusCode == 401 || error.statusCode == 403) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.authentication,
        TsPhoneProblemCode.authentication,
      );
    }
    if (error.statusCode case final status? when status >= 500) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.serviceUnavailable,
      );
    }
    return TsPhoneProblem(
      code == TsPhoneProblemCode.authentication
          ? TsPhoneProblemKind.authentication
          : code == TsPhoneProblemCode.incompatible
          ? TsPhoneProblemKind.incompatible
          : TsPhoneProblemKind.request,
      code,
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
    required this.type,
    required this.payload,
    required this.at,
    this.instanceEpoch,
    this.sessionGeneration,
  });

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

abstract interface class TsPhoneModelGateway {
  Future<List<PhoneModel>> models();
  Future<SessionSummary> selectModel(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    PhoneModel model,
  );
}

String createTsPhoneClientMessageId() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final entropy = List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'phone-$timestamp-$entropy';
}
