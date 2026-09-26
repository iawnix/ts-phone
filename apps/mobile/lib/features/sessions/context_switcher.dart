import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';
import 'package:intl/intl.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/workspace.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/presentation.dart';

typedef ContextSessionLoader =
    Future<List<SessionSummary>> Function(WorkspaceSummary workspace);
typedef ContextSessionSelector =
    void Function(WorkspaceSummary workspace, SessionSummary session);
typedef ContextSessionCreator =
    Future<SessionSummary?> Function(WorkspaceSummary workspace);

/// Mobile context switcher for the current project and conversation.
///
/// The sheet owns the temporary selection so browsing another project never
/// replaces the active conversation until a session is chosen.
class ContextSwitcherSheet extends StatefulWidget {
  const ContextSwitcherSheet({
    super.key,
    required this.workspaces,
    required this.selectedWorkspace,
    required this.selectedSession,
    required this.initialSessions,
    required this.loadSessions,
    required this.onSessionSelected,
    this.onCreateSession,
    this.onCreateWorkspace,
    this.dismissOnSessionSelected = true,
    this.embedded = false,
  });

  final List<WorkspaceSummary> workspaces;
  final WorkspaceSummary selectedWorkspace;
  final SessionSummary? selectedSession;
  final List<SessionSummary>? initialSessions;
  final ContextSessionLoader loadSessions;
  final ContextSessionSelector onSessionSelected;
  final ContextSessionCreator? onCreateSession;
  final Future<WorkspaceSummary?> Function()? onCreateWorkspace;
  final bool dismissOnSessionSelected;
  final bool embedded;

  @override
  State<ContextSwitcherSheet> createState() => _ContextSwitcherSheetState();
}

class _ContextSwitcherSheetState extends State<ContextSwitcherSheet> {
  late List<WorkspaceSummary> _workspaces;
  late WorkspaceSummary _workspace;
  List<SessionSummary>? _sessions;
  Object? _error;
  bool _loading = false;
  bool _creating = false;
  bool _creatingWorkspace = false;

  @override
  void initState() {
    super.initState();
    _workspaces = List<WorkspaceSummary>.of(widget.workspaces);
    _workspace = widget.selectedWorkspace;
    _sessions = widget.initialSessions == null
        ? null
        : _prioritizeSessions(widget.initialSessions!);
    if (_sessions == null) unawaited(_loadSessions(_workspace));
  }

  @override
  void didUpdateWidget(covariant ContextSwitcherSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _workspaces = List<WorkspaceSummary>.of(widget.workspaces);
    final selectedId =
        oldWidget.selectedWorkspace.id != widget.selectedWorkspace.id
        ? widget.selectedWorkspace.id
        : _workspace.id;
    WorkspaceSummary? next;
    for (final workspace in _workspaces) {
      if (workspace.id == selectedId) {
        next = workspace;
        break;
      }
    }
    next ??= widget.selectedWorkspace;
    final nextWorkspace = next;
    if (nextWorkspace.id == _workspace.id) {
      _workspace = nextWorkspace;
      return;
    }
    _workspace = nextWorkspace;
    _sessions = null;
    _error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _workspace.id == nextWorkspace.id && _sessions == null) {
        unawaited(_loadSessions(nextWorkspace));
      }
    });
  }

  Future<void> _loadSessions(WorkspaceSummary workspace) async {
    setState(() {
      _workspace = workspace;
      _sessions = null;
      _error = null;
      _loading = true;
    });
    try {
      final sessions = await widget.loadSessions(workspace);
      if (!mounted || _workspace.id != workspace.id) return;
      setState(() => _sessions = _prioritizeSessions(sessions));
    } on Object catch (error) {
      if (mounted && _workspace.id == workspace.id) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && _workspace.id == workspace.id) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createSession() async {
    final create = widget.onCreateSession;
    if (create == null || _creating) return;
    setState(() => _creating = true);
    try {
      final session = await create(_workspace);
      if (!mounted || session == null) return;
      widget.onSessionSelected(_workspace, session);
      if (widget.dismissOnSessionSelected) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _createWorkspace() async {
    final create = widget.onCreateWorkspace;
    if (create == null || _creatingWorkspace) return;
    setState(() => _creatingWorkspace = true);
    try {
      final workspace = await create();
      if (!mounted || workspace == null) return;
      setState(() {
        _workspaces = [
          ..._workspaces.where((value) => value.id != workspace.id),
          workspace,
        ];
        _workspace = workspace;
        _sessions = null;
        _error = null;
      });
      unawaited(_loadSessions(workspace));
    } finally {
      if (mounted) setState(() => _creatingWorkspace = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sessions = _sessions;
    final content = ListView(
      shrinkWrap: !widget.embedded,
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        TsPhoneSpacing.small,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _SheetHeader(title: l10n.workspaces)),
            if (widget.onCreateWorkspace != null)
              IconButton(
                key: const ValueKey('context-new-workspace'),
                onPressed: _creatingWorkspace ? null : _createWorkspace,
                tooltip: l10n.newProject,
                icon: _creatingWorkspace
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.create_new_folder_outlined),
              ),
          ],
        ),
        const SizedBox(height: TsPhoneSpacing.xSmall),
        for (final workspace in _workspaces)
          _ContextRow(
            icon: switch (workspace.runtimeState) {
              RuntimeState.running => AppIcons.motion_photos_on_outlined,
              RuntimeState.connecting => AppIcons.sync_rounded,
              RuntimeState.offline => AppIcons.cloud_off_outlined,
              RuntimeState.recoveryRequired => AppIcons.error_outline_rounded,
              RuntimeState.idle => AppIcons.folder_outlined,
            },
            title: workspace.name,
            selected: workspace.id == _workspace.id,
            onTap: workspace.id == _workspace.id
                ? null
                : () => _loadSessions(workspace),
          ),
        const SizedBox(height: TsPhoneSpacing.large),
        Row(
          children: <Widget>[
            Expanded(child: _SheetHeader(title: l10n.sessions)),
            if (widget.onCreateSession != null)
              IconButton(
                key: const ValueKey('context-new-session'),
                onPressed: _creating ? null : _createSession,
                tooltip: l10n.newSession,
                icon: _creating
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.add_rounded),
              ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error case final error?)
          _ContextError(
            message: describeTsPhoneProblem(error).localizedMessage(l10n),
            onRetry: () => _loadSessions(_workspace),
          )
        else if (sessions?.isEmpty == true)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              l10n.noSessionHistoryTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final session in sessions ?? const <SessionSummary>[])
            _ContextRow(
              icon: switch (session.runtimeState) {
                RuntimeState.running => AppIcons.motion_photos_on_outlined,
                RuntimeState.connecting => AppIcons.sync_rounded,
                RuntimeState.offline => AppIcons.cloud_off_outlined,
                RuntimeState.recoveryRequired => AppIcons.error_outline_rounded,
                RuntimeState.idle => AppIcons.chat_bubble_outline_rounded,
              },
              title: session.localizedDisplayName(l10n),
              leadingLabel: session.runtimeState.localizedCompactLabel(l10n),
              subtitle: _sessionSubtitle(session, l10n),
              selected:
                  session.sessionId == widget.selectedSession?.sessionId &&
                  _workspace.id == widget.selectedWorkspace.id,
              onTap: () {
                widget.onSessionSelected(_workspace, session);
                if (widget.dismissOnSessionSelected) {
                  Navigator.of(context).pop();
                }
              },
            ),
      ],
    );
    if (widget.embedded) return SafeArea(child: content);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 640.0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight * 0.88),
            child: content,
          );
        },
      ),
    );
  }

  String? _sessionSubtitle(SessionSummary session, AppLocalizations l10n) {
    final updated = session.updatedAt?.toLocal();
    if (updated == null) return null;
    return DateFormat.MMMd(l10n.localeName).add_Hm().format(updated);
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leadingLabel,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? leadingLabel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TsPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TsPhoneRadii.small),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: leadingLabel == null
            ? Icon(
                icon,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              )
            : Semantics(
                label: leadingLabel,
                excludeSemantics: true,
                child: Tooltip(
                  message: leadingLabel!,
                  child: Icon(
                    icon,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? Icon(AppIcons.check_rounded, color: colors.primary)
            : null,
        onTap: null,
      ),
    );
  }
}

class _ContextError extends StatelessWidget {
  const _ContextError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: <Widget>[
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: TsPhoneSpacing.small),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(AppIcons.refresh_rounded),
          label: Text(context.l10n.retry),
        ),
      ],
    ),
  );
}

List<SessionSummary> _prioritizeSessions(List<SessionSummary> sessions) {
  final indexed = sessions.asMap().entries.toList(growable: false);
  indexed.sort((left, right) {
    final running =
        (right.value.runtimeState == RuntimeState.running ? 1 : 0) -
        (left.value.runtimeState == RuntimeState.running ? 1 : 0);
    if (running != 0) return running;
    return right.value.updatedAt?.compareTo(
          left.value.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ) ??
        left.key.compareTo(right.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}
