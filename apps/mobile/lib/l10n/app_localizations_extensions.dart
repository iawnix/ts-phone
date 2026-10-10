import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/corhub_api.dart';
import '../data/link_pairing.dart';
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
    ConnectionValidationReason.invalidServerId => l10n.validationServerId,
    ConnectionValidationReason.invalidDeviceId => l10n.validationDeviceId,
    ConnectionValidationReason.invalidToken => l10n.validationTokenInvalid,
  };
}

extension LinkPairingLocalizations on LinkPairingException {
  String localizedMessage(AppLocalizations l10n) => switch (code) {
    'invalid_pairing_code' => l10n.validationPairingCode,
    'invalid_device_name' => l10n.validationDeviceName,
    'invalid_pairing' => l10n.pairingInvalidOrExpired,
    'relay_unavailable' => l10n.pairingRelayUnavailable,
    'invalid_response' => l10n.pairingRelayResponseInvalid,
    'unsupported_protocol' => l10n.pairingProtocolUnsupported,
    _ => l10n.pairingRejected,
  };
}

extension CorHubProblemLocalizations on CorHubProblem {
  String localizedMessage(AppLocalizations l10n) => switch (code) {
    CorHubProblemCode.apiRouteMissing => l10n.problemApiRouteMissing,
    CorHubProblemCode.queueStorageUnavailable => l10n.problemQueueStorage,
    CorHubProblemCode.queueCapacity => l10n.problemQueueCapacity,
    CorHubProblemCode.queueRecovery => l10n.problemQueueRecovery,
    CorHubProblemCode.providerUnavailable => l10n.problemProviderUnavailable,
    CorHubProblemCode.providerRateLimited => l10n.problemProviderRateLimited,
    CorHubProblemCode.providerAuthFailed => l10n.problemProviderAuthFailed,
    CorHubProblemCode.providerError => l10n.problemProviderError,
    CorHubProblemCode.generationIncomplete => l10n.problemGenerationIncomplete,
    CorHubProblemCode.incompatible => l10n.problemIncompatible,
    CorHubProblemCode.modelUnavailable => l10n.problemModelUnavailable,
    CorHubProblemCode.modelAuthMissing => l10n.problemModelAuthMissing,
    CorHubProblemCode.modelStorageUnavailable =>
      l10n.problemModelStorageUnavailable,
    CorHubProblemCode.modelCheckFailed => l10n.problemModelCheckFailed,
    CorHubProblemCode.promptRejected => l10n.problemPromptRejected,
    CorHubProblemCode.runtimeExtensionError =>
      l10n.problemRuntimeExtensionError,
    CorHubProblemCode.deliveryUncertain => l10n.problemDeliveryUncertain,
    CorHubProblemCode.authentication => l10n.problemAuthentication,
    CorHubProblemCode.sessionOffline => l10n.problemSessionOffline,
    CorHubProblemCode.sessionChanged => l10n.problemSessionChanged,
    CorHubProblemCode.agentRunChanged => l10n.problemAgentRunChanged,
    CorHubProblemCode.managementChanged => l10n.problemManagementChanged,
    CorHubProblemCode.activationExternalOwner => l10n.activationExternalOwner,
    CorHubProblemCode.activationUpgradeRequired =>
      l10n.activationUpgradeRequired,
    CorHubProblemCode.activationWriterActive => l10n.activationWriterActive,
    CorHubProblemCode.activationInspectionFailed =>
      l10n.activationInspectionFailed,
    CorHubProblemCode.activationGuardInvalid => l10n.activationGuardInvalid,
    CorHubProblemCode.activationFailed => l10n.activationFailed,
    CorHubProblemCode.activationOutcomeUnknown => l10n.activationOutcomeUnknown,
    CorHubProblemCode.activationCapacity => l10n.activationCapacity,
    CorHubProblemCode.runtimeRecoveryRequired =>
      l10n.activationRecoveryRequired,
    CorHubProblemCode.resourcesBusy => l10n.problemResourcesBusy,
    CorHubProblemCode.preflightUnavailable => l10n.problemPreflightUnavailable,
    CorHubProblemCode.managementCapacity => l10n.problemManagementCapacity,
    CorHubProblemCode.managementUnsupported =>
      l10n.problemManagementUnsupported,
    CorHubProblemCode.serviceUnavailable => l10n.problemServiceUnavailable,
    CorHubProblemCode.connectionFailed => l10n.problemConnectionFailed,
    CorHubProblemCode.requestTimeout => l10n.problemRequestTimeout,
    CorHubProblemCode.requestFailed => l10n.problemRequestFailed,
    CorHubProblemCode.networkRetrying => l10n.networkRetrying,
    CorHubProblemCode.invalidMessage => l10n.invalidMessage,
    CorHubProblemCode.invalidHistoryMessage => l10n.invalidHistoryMessage,
  };
}
