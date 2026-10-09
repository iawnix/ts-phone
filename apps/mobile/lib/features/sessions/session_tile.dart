import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/workspace.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../theme/app_icons.dart';
import '../../widgets/presentation.dart';

class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    required this.onTap,
    this.selected = false,
    this.trailing,
    this.leading,
  });
  final SessionSummary session;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? trailing;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final updated = session.updatedAt?.toLocal();
    return ListTile(
      key: ValueKey('session-${session.sessionId}'),
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      selected: selected,
      leading:
          leading ??
          TsRuntimeStatusGlyph(
            state: session.runtimeState,
            label: session.runtimeState.localizedCompactLabel(l10n),
            idleIcon: AppIcons.chat_bubble_outline_rounded,
            selected: selected,
          ),
      title: Text(
        session.localizedDisplayName(l10n),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: updated == null
          ? null
          : Text(
              DateFormat.MMMd(l10n.localeName).add_Hm().format(updated),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing:
          trailing ??
          (selected
              ? Icon(
                  AppIcons.check_rounded,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null),
      onTap: onTap,
    );
  }
}
