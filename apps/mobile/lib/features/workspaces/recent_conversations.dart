import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/settings_store.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/workspace.dart';

typedef OpenConversation =
    void Function(WorkspaceSummary workspace, SessionSummary session);

class RecentConversations extends StatefulWidget {
  const RecentConversations({
    super.key,
    required this.workspaces,
    required this.gateway,
    required this.endpoint,
    required this.onSelected,
    this.selectionStore,
  });

  final List<WorkspaceSummary> workspaces;
  final TsPhoneGateway gateway;
  final String endpoint;
  final ConversationSelectionStore? selectionStore;
  final OpenConversation onSelected;

  @override
  State<RecentConversations> createState() => _RecentConversationsState();
}

class _RecentConversationsState extends State<RecentConversations> {
  List<(WorkspaceSummary, SessionSummary)> _recent = [];
  bool _loading = true;
  bool _incomplete = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _incomplete = false;
    });
    (String, String)? last;
    try {
      last = await widget.selectionStore?.loadConversation(widget.endpoint);
    } on Object {
      // The recent-selection preference is optional, not an authorization source.
    }
    if (!mounted || generation != _generation) return;
    var cursor = 0;
    var incomplete = false;
    final recent = <(WorkspaceSummary, SessionSummary)>[];
    int compare(
      (WorkspaceSummary, SessionSummary) a,
      (WorkspaceSummary, SessionSummary) b,
    ) {
      final aLast = (a.$1.id, a.$2.sessionId) == last;
      final bLast = (b.$1.id, b.$2.sessionId) == last;
      if (aLast != bLast) return aLast ? -1 : 1;
      final byTime = (b.$2.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.$2.updatedAt?.millisecondsSinceEpoch ?? 0,
      );
      if (byTime != 0) return byTime;
      final byWorkspace = a.$1.id.compareTo(b.$1.id);
      return byWorkspace != 0
          ? byWorkspace
          : a.$2.sessionId.compareTo(b.$2.sessionId);
    }

    // Only summary endpoints are used. Limit request concurrency and retained rows.
    Future<void> worker() async {
      while (mounted &&
          generation == _generation &&
          cursor < widget.workspaces.length) {
        final workspace = widget.workspaces[cursor++];
        try {
          final sessions = await widget.gateway.listSessions(workspace.id);
          if (!mounted || generation != _generation) return;
          recent.addAll(
            sessions
                .where(
                  (session) => session.lifecycleState == LifecycleState.active,
                )
                .map((session) => (workspace, session)),
          );
          recent.sort(compare);
          if (recent.length > 5) recent.removeRange(5, recent.length);
          setState(() => _recent = List.of(recent));
        } on Object {
          incomplete = true;
        }
      }
    }

    await Future.wait(
      List.generate(widget.workspaces.length.clamp(0, 3), (_) => worker()),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _recent = recent;
      _loading = false;
      _incomplete = incomplete;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              l10n.recentConversations,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (_loading && _recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (!_loading && _recent.isEmpty && !_incomplete)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              child: Text(
                l10n.noRecentConversations,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final (workspace, session) in _recent)
            ListTile(
              key: ValueKey(
                'recent-session-${workspace.id}-${session.sessionId}',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              title: Text(
                session.localizedDisplayName(l10n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                [
                  workspace.name,
                  if (session.updatedAt case final date?)
                    DateFormat.MMMd(
                      l10n.localeName,
                    ).add_Hm().format(date.toLocal()),
                ].join(' · '),
              ),
              trailing: Icon(
                session.isStreaming ? Icons.hourglass_top : Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onTap:
                  session.canPrompt ||
                      session.historyAvailable ||
                      session.canActivate
                  ? () => widget.onSelected(workspace, session)
                  : null,
            ),
          if (_incomplete)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.recentConversationsIncomplete,
                style: theme.textTheme.bodySmall,
              ),
              trailing: IconButton(
                onPressed: _loading ? null : _load,
                tooltip: l10n.retry,
                icon: const Icon(Icons.refresh),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
