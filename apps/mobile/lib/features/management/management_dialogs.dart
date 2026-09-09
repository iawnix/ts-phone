import 'package:flutter/material.dart';

import '../../l10n/app_localizations_extensions.dart';
import '../../models/workspace.dart';
import '../../models/phone_model.dart';
import '../../data/ts_phone_api.dart';
import '../chat/model_picker.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';

class SessionDraft {
  const SessionDraft({required this.accessMode, this.name, this.model});

  final SessionAccessMode accessMode;
  final String? name;
  final String? model;
}

Future<String?> showNameEditor(
  BuildContext context, {
  required String title,
  required String fieldLabel,
  required String actionLabel,
  String initialValue = '',
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _NameEditorSheet(
    title: title,
    fieldLabel: fieldLabel,
    actionLabel: actionLabel,
    initialValue: initialValue,
  ),
);

Future<SessionDraft?> showSessionCreator(
  BuildContext context, {
  TsPhoneModelGateway? models,
}) => showModalBottomSheet<SessionDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _SessionCreatorSheet(models: models),
);

class _NameEditorSheet extends StatefulWidget {
  const _NameEditorSheet({
    required this.title,
    required this.fieldLabel,
    required this.actionLabel,
    required this.initialValue,
  });

  final String title;
  final String fieldLabel;
  final String actionLabel;
  final String initialValue;

  @override
  State<_NameEditorSheet> createState() => _NameEditorSheetState();
}

class _NameEditorSheetState extends State<_NameEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    ActionFeedback.tap();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return _KeyboardSafeSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: TsPhoneSpacing.large),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: widget.fieldLabel),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: TsPhoneSpacing.medium),
          FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
        ],
      ),
    );
  }
}

class _SessionCreatorSheet extends StatefulWidget {
  const _SessionCreatorSheet({this.models});
  final TsPhoneModelGateway? models;

  @override
  State<_SessionCreatorSheet> createState() => _SessionCreatorSheetState();
}

class _SessionCreatorSheetState extends State<_SessionCreatorSheet> {
  final TextEditingController _nameController = TextEditingController();
  PhoneModel? _model;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    ActionFeedback.tap();
    Navigator.of(context).pop(
      SessionDraft(
        accessMode: SessionAccessMode.controller,
        name: _optionalText(_nameController.text),
        model: _model?.reference,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _KeyboardSafeSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.newSession,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: TsPhoneSpacing.large),
          TextField(
            controller: _nameController,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.sessionNameOptional,
            ),
          ),
          const SizedBox(height: TsPhoneSpacing.small),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_rounded),
            title: Text(
              _model?.name ?? context.l10n.hostDefaultModel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _model == null ? null : Text(_model!.provider),
            trailing: _model == null
                ? const Icon(Icons.chevron_right_rounded)
                : IconButton(
                    onPressed: () => setState(() => _model = null),
                    tooltip: context.l10n.hostDefaultModel,
                    icon: const Icon(Icons.close_rounded),
                  ),
            onTap: widget.models == null
                ? null
                : () async {
                    final model = await showModelPicker(
                      context,
                      gateway: widget.models!,
                      selected: _model?.reference,
                    );
                    if (mounted && model != null) {
                      setState(() => _model = model);
                    }
                  },
          ),
          const SizedBox(height: TsPhoneSpacing.medium),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.add_comment_outlined),
            label: Text(context.l10n.createSession),
          ),
        ],
      ),
    );
  }
}

String? _optionalText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<bool> confirmMoveToTrash(
  BuildContext context, {
  required bool project,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          project
              ? context.l10n.projectDeleteTitle
              : context.l10n.sessionDeleteTitle,
        ),
        content: Text(
          project
              ? context.l10n.projectDeleteMessage
              : context.l10n.sessionDeleteMessage,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.moveToRecentlyDeleted),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> confirmPermanentDeletion(
  BuildContext context, {
  required String resourceId,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _PermanentDeletionDialog(resourceId: resourceId),
    ) ??
    false;

class _PermanentDeletionDialog extends StatefulWidget {
  const _PermanentDeletionDialog({required this.resourceId});

  final String resourceId;

  @override
  State<_PermanentDeletionDialog> createState() =>
      _PermanentDeletionDialogState();
}

class _PermanentDeletionDialogState extends State<_PermanentDeletionDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.permanentDeleteTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(context.l10n.permanentDeleteMessage(widget.resourceId)),
            const SizedBox(height: TsPhoneSpacing.large),
            TextField(
              controller: _controller,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.l10n.confirmationValue,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _controller.text == widget.resourceId
              ? () => Navigator.of(context).pop(true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: Text(context.l10n.deletePermanently),
        ),
      ],
    );
  }
}

Future<void> showDeletionBlockers(
  BuildContext context,
  WorkspaceDeletionPreflight preflight,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _KeyboardSafeSheet(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.l10n.deletionBlockedTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: TsPhoneSpacing.small),
        Text(context.l10n.deletionBlockedMessage),
        const SizedBox(height: TsPhoneSpacing.large),
        _BlockerRow(
          icon: Icons.memory_outlined,
          label: context.l10n.activeWorkers,
          count: preflight.activeWorkers,
        ),
        _BlockerRow(
          icon: Icons.science_outlined,
          label: context.l10n.remoteCalculations,
          count: preflight.remoteCalculations,
        ),
        _BlockerRow(
          icon: Icons.approval_outlined,
          label: context.l10n.pendingApprovals,
          count: preflight.pendingApprovals,
        ),
        _BlockerRow(
          icon: Icons.sync_problem_outlined,
          label: context.l10n.unresolvedRemoteEffects,
          count: preflight.unresolvedRemoteEffects,
        ),
        if (preflight.pendingCommands > 0)
          _BlockerRow(
            icon: Icons.playlist_play_rounded,
            label: context.l10n.commandQueue,
            count: preflight.pendingCommands,
          ),
      ],
    ),
  ),
);

class LifecycleSwitcher extends StatelessWidget {
  const LifecycleSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
    this.vertical = false,
    this.activeLabel,
    this.activeIcon = Icons.chat_bubble_outline,
    this.tooltip,
  });

  final LifecycleState value;
  final ValueChanged<LifecycleState> onChanged;
  final bool vertical;
  final String? activeLabel;
  final IconData activeIcon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final entries = <(LifecycleState, IconData, String)>[
      (
        LifecycleState.active,
        activeIcon,
        activeLabel ?? context.l10n.activeItems,
      ),
      (
        LifecycleState.archived,
        Icons.archive_outlined,
        context.l10n.archivedItems,
      ),
      (
        LifecycleState.trashed,
        Icons.delete_outline,
        context.l10n.recentlyDeleted,
      ),
    ];
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            ListTile(
              key: ValueKey('lifecycle-${entry.$1.name}'),
              dense: true,
              leading: Icon(entry.$2, size: 22),
              title: Text(entry.$3),
              selected: value == entry.$1,
              trailing: value == entry.$1
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
              onTap: value == entry.$1 ? null : () => onChanged(entry.$1),
            ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<LifecycleState>(
        key: const ValueKey('lifecycle-filter'),
        tooltip:
            '${tooltip ?? context.l10n.sessionViews}: ${entries.firstWhere((entry) => entry.$1 == value).$3}',
        icon: Icon(
          value == LifecycleState.active
              ? Icons.filter_list_rounded
              : value == LifecycleState.archived
              ? Icons.archive_outlined
              : Icons.delete_outline,
          size: 22,
        ),
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final entry in entries)
            PopupMenuItem(
              value: entry.$1,
              child: Row(
                children: [
                  Icon(entry.$2, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.$3)),
                  if (value == entry.$1) const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyboardSafeSheet extends StatelessWidget {
  const _KeyboardSafeSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        0,
        TsPhoneSpacing.large,
        MediaQuery.viewInsetsOf(context).bottom + TsPhoneSpacing.large,
      ),
      child: SingleChildScrollView(child: child),
    );
  }
}

class _BlockerRow extends StatelessWidget {
  const _BlockerRow({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: count > 0 ? colors.error : colors.outline),
      title: Text(label),
      trailing: TsMonoText('$count'),
    );
  }
}
