import 'dart:async';
import 'dart:math';

import '../models/phone_model.dart';
import '../models/workspace.dart';

class CorHubApiException implements Exception {
  const CorHubApiException(
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

enum CorHubProblemKind { authentication, incompatible, unavailable, request }

enum CorHubProblemCode {
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
  invalidHistoryMessage,
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

class CorHubProblem {
  const CorHubProblem(this.kind, this.code);

  final CorHubProblemKind kind;
  final CorHubProblemCode code;
}

CorHubProblem describeCorHubProblem(Object error) {
  if (error is FormatException) {
    return const CorHubProblem(
      CorHubProblemKind.incompatible,
      CorHubProblemCode.incompatible,
    );
  }
  if (error is TimeoutException) {
    return const CorHubProblem(
      CorHubProblemKind.unavailable,
      CorHubProblemCode.requestTimeout,
    );
  }
  if (error is CorHubApiException) {
    final code = switch (error.code) {
      'authentication' || 'unauthorized' => CorHubProblemCode.authentication,
      'request_timeout' => CorHubProblemCode.requestTimeout,
      'session_offline' => CorHubProblemCode.sessionOffline,
      'workspace_busy' || 'session_busy' => CorHubProblemCode.resourcesBusy,
      'turn_mismatch' => CorHubProblemCode.agentRunChanged,
      'session_lifecycle_unavailable' =>
        CorHubProblemCode.managementUnsupported,
      'session_start_timeout' ||
      'request_uncertain' => CorHubProblemCode.deliveryUncertain,
      'service_unavailable' ||
      'connection_closed' => CorHubProblemCode.serviceUnavailable,
      'session_not_found' ||
      'workspace_not_found' => CorHubProblemCode.sessionChanged,
      'service_not_found' ||
      'service_member_not_found' ||
      'version' ||
      'protocol_mismatch' ||
      'method_not_found' => CorHubProblemCode.incompatible,
      'model_unavailable' => CorHubProblemCode.modelUnavailable,
      'invalid_model' ||
      'model_not_found' ||
      'model_unconfigured' => CorHubProblemCode.modelUnavailable,
      'model_auth_missing' => CorHubProblemCode.modelAuthMissing,
      'provider_unavailable' => CorHubProblemCode.providerUnavailable,
      'provider_rate_limited' => CorHubProblemCode.providerRateLimited,
      'provider_auth_failed' => CorHubProblemCode.providerAuthFailed,
      'provider_error' => CorHubProblemCode.providerError,
      'prompt_rejected' => CorHubProblemCode.promptRejected,
      'runtime_extension_error' => CorHubProblemCode.runtimeExtensionError,
      'generation_incomplete' => CorHubProblemCode.generationIncomplete,
      'agent_run_stale' ||
      'agent_not_running' => CorHubProblemCode.agentRunChanged,
      _ => CorHubProblemCode.requestFailed,
    };
    if (error.statusCode == 401 || error.statusCode == 403) {
      return const CorHubProblem(
        CorHubProblemKind.authentication,
        CorHubProblemCode.authentication,
      );
    }
    if (error.statusCode case final status? when status >= 500) {
      return const CorHubProblem(
        CorHubProblemKind.unavailable,
        CorHubProblemCode.serviceUnavailable,
      );
    }
    return CorHubProblem(
      code == CorHubProblemCode.authentication
          ? CorHubProblemKind.authentication
          : code == CorHubProblemCode.incompatible
          ? CorHubProblemKind.incompatible
          : CorHubProblemKind.request,
      code,
    );
  }
  return const CorHubProblem(
    CorHubProblemKind.unavailable,
    CorHubProblemCode.connectionFailed,
  );
}

class CorHubEvent {
  const CorHubEvent({
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

class CorHubMessageSnapshot {
  const CorHubMessageSnapshot({
    required this.sessionId,
    required this.sessionRevision,
    required this.messages,
    required this.lastEventId,
    this.activeAgentRunId,
    this.messageIds,
  });

  final String sessionId;
  final String sessionRevision;
  final List<Object?> messages;
  final String lastEventId;
  final String? activeAgentRunId;
  final List<String>? messageIds;
}

abstract interface class CorHubGateway {
  Future<Map<String, Object?>> version();
  Future<List<WorkspaceSummary>> listWorkspaces();
  Future<List<SessionSummary>> listSessions(String workspaceId);
  Future<CorHubMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId,
  );
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
  Stream<CorHubEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  });
  void close();
}

abstract interface class CorHubModelGateway {
  Future<List<PhoneModel>> models();
  Future<SessionSummary> selectModel(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    PhoneModel model,
  );
}

String createCorHubClientMessageId() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final entropy = List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'phone-$timestamp-$entropy';
}
