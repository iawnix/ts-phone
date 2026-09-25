import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/presentation.dart';
import 'session_view_state.dart';

/// A single, actionable notice for the current session.
///
/// Keeping this as one widget prevents connection, recovery and operation
/// errors from competing for the same vertical space.  The detailed error
/// remains available through the localized message, while the action is kept
/// deliberately small and safe.
class SessionNoticeView extends StatelessWidget {
  const SessionNoticeView({
    super.key,
    required this.state,
    required this.problem,
    required this.onRetry,
  });

  final SessionViewState state;
  final TsPhoneProblem? problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final notice = state.notice;
    if (notice == null) {
      return AnimatedSwitcher(
        duration: TsPhoneMotion.resolveFade(context, TsPhoneMotion.standard),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: const SizedBox(key: ValueKey<String>('session-notice-empty')),
      );
    }
    final l10n = context.l10n;
    final (icon, tone, message) = switch (notice) {
      SessionNoticeKind.error => (
        AppIcons.error_outline_rounded,
        TsInfoTone.error,
        problem?.localizedMessage(l10n) ?? l10n.problemRequestFailed,
      ),
      SessionNoticeKind.recovery => (
        AppIcons.restore_rounded,
        TsInfoTone.error,
        l10n.generationDisconnectedBanner,
      ),
      SessionNoticeKind.offline => (
        AppIcons.cloud_off_outlined,
        TsInfoTone.warning,
        l10n.tspiDisconnectedBanner,
      ),
    };

    final action = switch (notice) {
      SessionNoticeKind.error => IconButton(
        onPressed: onRetry,
        tooltip: l10n.reconnect,
        icon: const Icon(AppIcons.refresh_rounded),
      ),
      SessionNoticeKind.recovery => IconButton(
        onPressed: onRetry,
        tooltip: l10n.checkAgain,
        icon: const Icon(AppIcons.refresh_rounded),
      ),
      SessionNoticeKind.offline => IconButton(
        onPressed: onRetry,
        tooltip: l10n.checkAgain,
        icon: const Icon(AppIcons.refresh_rounded),
      ),
    };

    return AnimatedSwitcher(
      duration: TsPhoneMotion.resolveFade(context, TsPhoneMotion.standard),
      switchInCurve: Curves.easeOutCubic,
      // Keep the exit responsive so a recovery/error update can be replaced
      // immediately without making the user wait for a slow fade.
      switchOutCurve: Curves.easeOutCubic,
      child: TsInfoBand(
        key: ValueKey<SessionNoticeKind>(notice),
        icon: icon,
        message: message,
        tone: tone,
        action: action,
      ),
    );
  }
}
