import 'package:flutter/material.dart';

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
    required this.onCopyStartCommand,
  });

  final SessionViewState state;
  final TsPhoneProblem? problem;
  final VoidCallback onRetry;
  final VoidCallback onCopyStartCommand;

  @override
  Widget build(BuildContext context) {
    final notice = state.notice;
    if (notice == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final (icon, tone, message) = switch (notice) {
      SessionNoticeKind.error => (
        Icons.error_outline_rounded,
        TsInfoTone.error,
        problem?.localizedMessage(l10n) ?? l10n.problemRequestFailed,
      ),
      SessionNoticeKind.recovery => (
        Icons.restore_rounded,
        TsInfoTone.error,
        l10n.generationDisconnectedBanner,
      ),
      SessionNoticeKind.offline => (
        Icons.cloud_off_outlined,
        TsInfoTone.warning,
        l10n.tspiDisconnectedBanner,
      ),
    };

    final action = switch (notice) {
      SessionNoticeKind.error => IconButton(
        onPressed: onRetry,
        tooltip: l10n.reconnect,
        icon: const Icon(Icons.refresh_rounded),
      ),
      SessionNoticeKind.recovery => IconButton(
        onPressed: onRetry,
        tooltip: l10n.checkAgain,
        icon: const Icon(Icons.refresh_rounded),
      ),
      SessionNoticeKind.offline => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: onCopyStartCommand,
            tooltip: l10n.copyStartCommand,
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            onPressed: onRetry,
            tooltip: l10n.checkAgain,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    };

    return AnimatedSwitcher(
      duration: TsPhoneMotion.resolve(context, TsPhoneMotion.standard),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
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
