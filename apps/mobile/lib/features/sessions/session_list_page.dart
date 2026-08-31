import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../chat/chat_page.dart';

typedef SessionGatewayBuilder =
    TsPhoneGateway Function(ConnectionSettings settings);

class SessionListPage extends StatefulWidget {
  const SessionListPage({
    super.key,
    required this.settings,
    required this.workspace,
    this.initialSessions,
    this.gatewayBuilder,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final List<SessionSummary>? initialSessions;
  final SessionGatewayBuilder? gatewayBuilder;

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage>
    with WidgetsBindingObserver {
  late final TsPhoneGateway _api;
  List<SessionSummary>? _sessions;
  TsPhoneProblem? _problem;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api =
        widget.gatewayBuilder?.call(widget.settings) ??
        TsPhoneApi(widget.settings);
    _sessions = widget.initialSessions == null
        ? null
        : _prioritizeSessions(widget.initialSessions!);
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }

  Future<void> _refresh({bool announce = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    if (announce) ActionFeedback.tap();
    try {
      final sessions = await _api.listSessions(widget.workspace.id);
      if (!mounted) return;
      setState(() {
        _sessions = _prioritizeSessions(sessions);
        _problem = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      if (announce) ActionFeedback.error();
      setState(() => _problem = describeTsPhoneProblem(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _open(SessionSummary session) async {
    ActionFeedback.selection();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatPage(
          settings: widget.settings,
          workspace: widget.workspace,
          session: session,
          recoveredSession:
              session.runtimeState == RuntimeState.recoveryRequired,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _copyStartCommand() async {
    ActionFeedback.tap();
    await Clipboard.setData(
      ClipboardData(text: './TSPi --workspace ${widget.workspace.id} --phone'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.startCommandCopied),
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: TsGlassAppBar(
        title: Text(widget.workspace.name),
        actions: <Widget>[
          IconButton(
            onPressed: _refreshing ? null : () => _refresh(announce: true),
            tooltip: _refreshing ? l10n.refreshing : l10n.refreshSessions,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: TsPageBackdrop(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final l10n = context.l10n;
    if (_sessions == null && _problem == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions == null) {
      return _SessionError(problem: _problem!, onRetry: _refresh);
    }
    if (_sessions!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 72, 0, 24),
          children: <Widget>[
            TsEmptyState(
              icon: Icons.history_rounded,
              title: l10n.noSessionHistoryTitle,
              message: l10n.noSessionHistoryMessage,
              action: FilledButton.icon(
                onPressed: _copyStartCommand,
                icon: const Icon(Icons.copy_outlined),
                label: Text(l10n.copyStartCommand),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: <Widget>[
        if (_problem != null)
          TsInfoBand(
            icon: Icons.cloud_off_outlined,
            message: l10n.sessionStateStale(_problem!.localizedMessage(l10n)),
            tone: TsInfoTone.error,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: TsPhoneSpacing.xLarge),
              itemCount: _sessions!.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final liveCount = _sessions!
                      .where((session) => session.canPrompt)
                      .length;
                  return TsSectionHeader(
                    title: l10n.sessions,
                    caption:
                        '${l10n.sessionCount(_sessions!.length)} · ${l10n.liveSessionCount(liveCount)}',
                  );
                }
                final session = _sessions![index - 1];
                return _SessionTile(
                  session: session,
                  onTap: () => _open(session),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

List<SessionSummary> _prioritizeSessions(List<SessionSummary> sessions) {
  final indexed = sessions.asMap().entries.toList(growable: false);
  indexed.sort((left, right) {
    final priority = _sessionDisplayPriority(
      left.value,
    ).compareTo(_sessionDisplayPriority(right.value));
    return priority != 0 ? priority : left.key.compareTo(right.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

int _sessionDisplayPriority(SessionSummary session) {
  if (session.isStreaming || session.runtimeState == RuntimeState.running) {
    return 0;
  }
  if (session.canPrompt && session.runtimeState == RuntimeState.idle) return 1;
  if (session.canPrompt || session.runtimeState == RuntimeState.connecting) {
    return 2;
  }
  if (session.runtimeState == RuntimeState.recoveryRequired) return 3;
  return 4;
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final SessionSummary session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = TsPhoneStatusTheme.resolve(context);
    final l10n = context.l10n;
    final stateColor = switch (session.runtimeState) {
      RuntimeState.running || RuntimeState.connecting => status.warning,
      RuntimeState.idle => status.connected,
      RuntimeState.recoveryRequired => status.error,
      RuntimeState.offline => colors.outline,
    };
    final accessIcon = session.historyOnly
        ? Icons.history_rounded
        : switch (session.accessMode) {
            SessionAccessMode.controller => Icons.admin_panel_settings_outlined,
            SessionAccessMode.observer => Icons.visibility_outlined,
          };
    final accessLabel = <String>[
      session.historyOnly
          ? l10n.historySession
          : session.accessMode.localizedLabel(l10n),
      if (session.displayModel != null) session.displayModel!,
    ].join(' · ');
    return TsStatusListTile(
      statusColor: stateColor,
      icon: accessIcon,
      title: session.localizedDisplayName(l10n),
      subtitle: accessLabel,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            accessLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          TsMonoText(
            l10n.sessionToken(session.shortId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
      trailing: _SessionStateBadge(
        state: session.runtimeState,
        color: stateColor,
      ),
      onTap: onTap,
    );
  }
}

class _SessionStateBadge extends StatelessWidget {
  const _SessionStateBadge({required this.state, required this.color});

  final RuntimeState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: state.localizedLabel(context.l10n),
      child: SizedBox(
        width: 108,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: TsStatusBadge(
                  label: state.localizedCompactLabel(context.l10n),
                  color: color,
                  compact: true,
                  pulsing: state == RuntimeState.idle,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 20, color: colors.outline),
          ],
        ),
      ),
    );
  }
}

class _SessionError extends StatelessWidget {
  const _SessionError({required this.problem, required this.onRetry});

  final TsPhoneProblem problem;
  final Future<void> Function({bool announce}) onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TsEmptyState(
      icon: Icons.cloud_off_outlined,
      title: l10n.loadSessionsFailed,
      message: problem.localizedMessage(l10n),
      action: IconButton.filledTonal(
        onPressed: () => onRetry(announce: true),
        tooltip: l10n.retry,
        icon: const Icon(Icons.refresh),
      ),
    );
  }
}
