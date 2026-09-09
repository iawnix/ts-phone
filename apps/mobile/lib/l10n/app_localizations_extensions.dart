import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/ts_phone_api.dart';
import '../features/chat/chat_controller.dart';
import '../models/connection_settings.dart';
import '../models/workspace.dart';
import 'app_localizations.dart';
import 'app_localizations_zh.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsZh();
}

extension RuntimeStateLocalizations on RuntimeState {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    RuntimeState.offline => l10n.runtimeOffline,
    RuntimeState.connecting => l10n.runtimeConnecting,
    RuntimeState.idle => l10n.runtimeIdle,
    RuntimeState.running => l10n.runtimeRunning,
    RuntimeState.recoveryRequired => l10n.runtimeRecoveryRequired,
  };

  String localizedCompactLabel(AppLocalizations l10n) => switch (this) {
    RuntimeState.offline => l10n.runtimeCompactOffline,
    RuntimeState.connecting => l10n.runtimeCompactConnecting,
    RuntimeState.idle => l10n.runtimeCompactReady,
    RuntimeState.running => l10n.runtimeCompactRunning,
    RuntimeState.recoveryRequired => l10n.runtimeCompactRecovery,
  };
}

extension SessionAccessModeLocalizations on SessionAccessMode {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    SessionAccessMode.controller => l10n.accessController,
    SessionAccessMode.observer => l10n.accessObserver,
  };
}

extension SessionSummaryLocalizations on SessionSummary {
  String localizedDisplayName(AppLocalizations l10n) {
    final name = sessionName?.trim();
    if (name?.isNotEmpty == true) return name!;
    final updated = updatedAt?.toLocal();
    return updated == null
        ? l10n.unnamedConversation
        : l10n.sessionFallback(
            DateFormat.MMMd(l10n.localeName).add_Hm().format(updated),
          );
  }
}

extension ConnectionValidationLocalizations on ConnectionValidationReason {
  String localizedMessage(AppLocalizations l10n) => switch (this) {
    ConnectionValidationReason.incompleteServerAddress =>
      l10n.validationCompleteServerAddress,
    ConnectionValidationReason.disallowedUrlComponents =>
      l10n.validationNoUrlComponents,
    ConnectionValidationReason.originOnly => l10n.validationOriginOnly,
    ConnectionValidationReason.httpsRequired => l10n.validationHttpsRequired,
    ConnectionValidationReason.invalidToken => l10n.validationTokenInvalid,
  };
}

extension TsPhoneProblemLocalizations on TsPhoneProblem {
  String localizedMessage(AppLocalizations l10n) => switch (code) {
    TsPhoneProblemCode.apiRouteMissing => l10n.problemApiRouteMissing,
    TsPhoneProblemCode.queueStorageUnavailable => l10n.problemQueueStorage,
    TsPhoneProblemCode.queueCapacity => l10n.problemQueueCapacity,
    TsPhoneProblemCode.queueRecovery => l10n.problemQueueRecovery,
    TsPhoneProblemCode.providerUnavailable => l10n.problemProviderUnavailable,
    TsPhoneProblemCode.providerRateLimited => l10n.problemProviderRateLimited,
    TsPhoneProblemCode.providerAuthFailed => l10n.problemProviderAuthFailed,
    TsPhoneProblemCode.providerError => l10n.problemProviderError,
    TsPhoneProblemCode.generationIncomplete => l10n.problemGenerationIncomplete,
    TsPhoneProblemCode.incompatible => l10n.problemIncompatible,
    TsPhoneProblemCode.modelUnavailable => l10n.problemModelUnavailable,
    TsPhoneProblemCode.modelAuthMissing => l10n.problemModelAuthMissing,
    TsPhoneProblemCode.modelStorageUnavailable =>
      l10n.problemModelStorageUnavailable,
    TsPhoneProblemCode.modelCheckFailed => l10n.problemModelCheckFailed,
    TsPhoneProblemCode.promptRejected => l10n.problemPromptRejected,
    TsPhoneProblemCode.runtimeExtensionError =>
      l10n.problemRuntimeExtensionError,
    TsPhoneProblemCode.deliveryUncertain => l10n.problemDeliveryUncertain,
    TsPhoneProblemCode.authentication => l10n.problemAuthentication,
    TsPhoneProblemCode.sessionOffline => l10n.problemSessionOffline,
    TsPhoneProblemCode.sessionChanged => l10n.problemSessionChanged,
    TsPhoneProblemCode.agentRunChanged => l10n.problemAgentRunChanged,
    TsPhoneProblemCode.managementChanged => l10n.problemManagementChanged,
    TsPhoneProblemCode.activationExternalOwner => l10n.activationExternalOwner,
    TsPhoneProblemCode.activationUpgradeRequired =>
      l10n.activationUpgradeRequired,
    TsPhoneProblemCode.activationWriterActive => l10n.activationWriterActive,
    TsPhoneProblemCode.activationInspectionFailed =>
      l10n.activationInspectionFailed,
    TsPhoneProblemCode.activationGuardInvalid => l10n.activationGuardInvalid,
    TsPhoneProblemCode.activationFailed => l10n.activationFailed,
    TsPhoneProblemCode.activationOutcomeUnknown =>
      l10n.activationOutcomeUnknown,
    TsPhoneProblemCode.activationCapacity => l10n.activationCapacity,
    TsPhoneProblemCode.runtimeRecoveryRequired =>
      l10n.activationRecoveryRequired,
    TsPhoneProblemCode.resourcesBusy => l10n.problemResourcesBusy,
    TsPhoneProblemCode.preflightUnavailable => l10n.problemPreflightUnavailable,
    TsPhoneProblemCode.managementCapacity => l10n.problemManagementCapacity,
    TsPhoneProblemCode.managementUnsupported =>
      l10n.problemManagementUnsupported,
    TsPhoneProblemCode.serviceUnavailable => l10n.problemServiceUnavailable,
    TsPhoneProblemCode.connectionFailed => l10n.problemConnectionFailed,
    TsPhoneProblemCode.requestTimeout => l10n.problemRequestTimeout,
    TsPhoneProblemCode.requestFailed => l10n.problemRequestFailed,
    TsPhoneProblemCode.networkRetrying => l10n.networkRetrying,
    TsPhoneProblemCode.invalidMessage => l10n.invalidMessage,
    TsPhoneProblemCode.invalidApproval => l10n.invalidApproval,
    TsPhoneProblemCode.invalidHistoryMessage => l10n.invalidHistoryMessage,
    TsPhoneProblemCode.approvalExpired => l10n.approvalExpired,
    TsPhoneProblemCode.approvalStale => l10n.approvalStale,
    TsPhoneProblemCode.approvalMissing => l10n.approvalMissing,
  };
}

extension ChatActivityLocalizations on ChatActivity {
  String localizedMessage(AppLocalizations l10n) => switch (kind) {
    ChatActivityKind.runningTool =>
      toolName == null ? l10n.toolRunningGeneric : l10n.toolRunning(toolName!),
    ChatActivityKind.toolFailed => l10n.toolFailed,
  };
}
