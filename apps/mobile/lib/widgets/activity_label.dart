import '../l10n/app_localizations.dart';

String activityLabel(String name, AppLocalizations l10n) => switch (name) {
  'read' => l10n.activityRead,
  'write' || 'edit' => l10n.activityWrite,
  'bash' => l10n.activityShell,
  'ts_state' => l10n.activityState,
  'ts_change' => l10n.activityChange,
  'ts_review' => l10n.activityReview,
  'ts_reply' => l10n.activityReply,
  'ts_calc' => l10n.activityCalculation,
  'ts_remote' => l10n.activityRemote,
  _ => name.replaceAll(RegExp(r'[_-]+'), ' ').trim(),
};
