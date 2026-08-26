import 'package:flutter/widgets.dart';

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
    return name?.isNotEmpty == true ? name! : l10n.sessionFallback(shortId);
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
    TsPhoneProblemCode.incompatible => l10n.problemIncompatible,
    TsPhoneProblemCode.authentication => l10n.problemAuthentication,
    TsPhoneProblemCode.sessionOffline => l10n.problemSessionOffline,
    TsPhoneProblemCode.sessionChanged => l10n.problemSessionChanged,
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
