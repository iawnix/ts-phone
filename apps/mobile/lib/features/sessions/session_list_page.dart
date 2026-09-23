import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_server_gateway.dart';
import '../../data/host_gateway.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/host_monitor.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../chat/chat_page.dart';
import '../monitors/monitor_page.dart';
import '../../l10n/host_monitor_localizations.dart';

typedef SessionGatewayBuilder =
    TsPhoneGateway Function(ConnectionSettings settings);

class SessionListPage extends StatefulWidget {
  const SessionListPage({
    super.key,
    required this.settings,
    required this.workspace,
    this.initialSessions,
    this.gatewayBuilder,
    this.onSelected,
    this.sidebarHeader,
    this.sidebarFooter,
    this.onCreateSession,
    this.creatingSession = false,
    this.selectedSessionId,
    this.refreshToken = 0,
    this.onSessionsChanged,
    this.sidebar = false,
    this.onBack,
    this.onOpenSettings,
  });

  final ConnectionSettings settings;
  final WorkspaceSummary workspace;
  final List<SessionSummary>? initialSessions;
  final SessionGatewayBuilder? gatewayBuilder;
  final ValueChanged<SessionSummary>? onSelected;
  final Widget? sidebarHeader;
  final Widget? sidebarFooter;
  final VoidCallback? onCreateSession;
  final bool creatingSession;
  final String? selectedSessionId;
  final int refreshToken;
  final ValueChanged<List<SessionSummary>>? onSessionsChanged;
  final bool sidebar;
  final VoidCallback? onBack;
  final VoidCallback? onOpenSettings;

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage>
    with WidgetsBindingObserver {
  late final TsPhoneGateway _gateway;
  List<SessionSummary>? _sessions;
  TsPhoneProblem? _problem;
  String? _openingSessionId;
  String? _removingSessionId;
  bool _refreshing = false;
  bool _creatingSession = false;
  int _refreshGeneration = 0;
  String _query = '';

  AppServerSessionGateway? get _sessionsGateway =>
      _gateway is AppServerSessionGateway
      ? _gateway as AppServerSessionGateway
      : null;

  bool get _busy =>
      _openingSessionId != null ||
      _removingSessionId != null ||
      _creatingSession ||
      widget.creatingSession;

  Widget get _createIcon => _creatingSession || widget.creatingSession
      ? const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.add_comment_outlined, size: 22);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gateway =
        widget.gatewayBuilder?.call(widget.settings) ??
        HostGateway(widget.settings);
    _sessions = widget.initialSessions == null
        ? null
        : _prioritizeSessions(widget.initialSessions!);
    if (_sessions == null) unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant SessionListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_refresh(force: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gateway.close();
    super.dispose();
  }

  Future<void> _refresh({bool announce = false, bool force = false}) async {
    if (_refreshing && !force) return;
    final generation = ++_refreshGeneration;
    setState(() => _refreshing = true);
    if (announce) ActionFeedback.tap();
    try {
      final sessions = await _gateway.listSessions(widget.workspace.id);
      if (!mounted || generation != _refreshGeneration) return;
      final sorted = _prioritizeSessions(sessions);
      setState(() {
        _sessions = sorted;
        _problem = null;
      });
      widget.onSessionsChanged?.call(sorted);
    } on Object catch (error) {
      if (!mounted || generation != _refreshGeneration) return;
      if (announce) ActionFeedback.error();
      setState(() => _problem = describeTsPhoneProblem(error));
    } finally {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _open(SessionSummary session) async {
    if (_busy) return;
    setState(() => _openingSessionId = session.sessionId);
    ActionFeedback.selection();
    try {
      if (!session.runtimeState.isAvailable &&
          session.accessMode == SessionAccessMode.controller &&
          _gateway is SessionResumeGateway) {
        session = await (_gateway as SessionResumeGateway)
            .resumeWorkspaceSession(widget.workspace.id, session.sessionId);
        if (!mounted) return;
      }
      if (widget.onSelected case final select?) {
        select(session);
        return;
      }
      if (!mounted) return;
      await pushTsPhonePage<void>(
        context: context,
        builder: (context) => ChatPage(
          settings: widget.settings,
          workspace: widget.workspace,
          session: session,
          gateway: widget.gatewayBuilder?.call(widget.settings),
        ),
      );
      if (mounted) await _refresh();
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted) setState(() => _openingSessionId = null);
    }
  }

  Future<void> _create() async {
    if (widget.onCreateSession case final create?) {
      create();
      return;
    }
    final gateway = _sessionsGateway;
    if (_busy || gateway == null) return;
    setState(() => _creatingSession = true);
    try {
      final session = await gateway.createWorkspaceSession(widget.workspace.id);
      await _refresh(force: true);
      if (mounted) await _open(session);
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted) setState(() => _creatingSession = false);
    }
  }

  Future<void> _openMonitors() async {
    final gateway = _gateway;
    if (gateway is! HostMonitorGateway) return;
    await pushTsPhonePage<void>(
      context: context,
      builder: (context) => MonitorPage(
        workspace: widget.workspace,
        gateway: gateway as HostMonitorGateway,
      ),
    );
  }

  Future<void> _remove(SessionSummary session) async {
    final gateway = _sessionsGateway;
    if (_busy || gateway == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deletePermanently),
        content: Text(session.localizedDisplayName(context.l10n)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.deletePermanently),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _removingSessionId = session.sessionId);
    try {
      await gateway.removeWorkspaceSession(
        widget.workspace.id,
        session.sessionId,
      );
      if (mounted) await _refresh(force: true);
    } on Object catch (error) {
      if (mounted) _showProblem(error);
    } finally {
      if (mounted) setState(() => _removingSessionId = null);
    }
  }

  void _showProblem(Object error) {
    ActionFeedback.error();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            describeTsPhoneProblem(error).localizedMessage(context.l10n),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sidebar) return _buildSidebar();
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.workspace.name),
        actions: [
          if (_gateway is HostMonitorGateway)
            IconButton(
              key: const ValueKey('open-monitors'),
              onPressed: _openMonitors,
              tooltip: l10n.hostMonitors,
              icon: const Icon(Icons.notifications_active_outlined),
            ),
          if (_sessionsGateway != null || widget.onCreateSession != null)
            IconButton(
              key: const ValueKey('create-session'),
              onPressed: _busy ? null : _create,
              tooltip: l10n.newSession,
              icon: _createIcon,
            ),
          if (widget.onOpenSettings case final open?)
            IconButton(
              onPressed: open,
              tooltip: l10n.settings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: TsPageBackdrop(
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: TsPhoneSpacing.xLarge),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final sessions = _filteredSessions;
    return ListTileTheme(
      data: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        selectedColor: colors.onSurface,
      ),
      child: SafeArea(
        child: Column(
          children: [
            ?widget.sidebarHeader,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                key: const ValueKey('conversation-search'),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.searchConversations,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: colors.surfaceContainer,
                  border: const OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
            ),
            if (widget.onCreateSession != null || _sessionsGateway != null)
              ListTile(
                key: const ValueKey('sidebar-new-session'),
                leading: _createIcon,
                title: Text(l10n.newSession),
                onTap: _busy ? null : _create,
              ),
            if (_problem case final problem?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  problem.localizedMessage(l10n),
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _sessions == null && _problem == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        key: const ValueKey('sidebar-conversations'),
                        children: [
                          if (sessions.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(l10n.noMessages),
                            ),
                          for (final session in sessions)
                            Material(
                              color: Colors.transparent,
                              child: ListTile(
                                key: ValueKey(
                                  'sidebar-session-${session.sessionId}',
                                ),
                                selected:
                                    session.sessionId ==
                                    widget.selectedSessionId,
                                selectedTileColor: colors.surfaceContainer,
                                leading: _sessionLeading(session),
                                title: Text(
                                  session.localizedDisplayName(l10n),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: _busy ? null : () => _open(session),
                                trailing: _sessionTrailing(session),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            ?widget.sidebarFooter,
            if (_gateway is HostMonitorGateway)
              ListTile(
                key: const ValueKey('sidebar-monitors'),
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(l10n.hostMonitors),
                onTap: _openMonitors,
              ),
          ],
        ),
      ),
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
          children: [
            TsEmptyState(
              icon: Icons.chat_bubble_outline,
              title: l10n.noSessionHistoryTitle,
              message: l10n.noSessionHistoryMessage,
              action: _sessionsGateway == null && widget.onCreateSession == null
                  ? null
                  : FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: _createIcon,
                      label: Text(l10n.createSession),
                    ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_problem case final problem?)
          TsInfoBand(
            icon: Icons.cloud_off_outlined,
            message: l10n.sessionStateStale(problem.localizedMessage(l10n)),
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
                  final running = _sessions!
                      .where(
                        (session) =>
                            session.runtimeState == RuntimeState.running,
                      )
                      .length;
                  return TsSectionHeader(
                    title: l10n.sessions,
                    caption:
                        '${l10n.sessionCount(_sessions!.length)} · ${l10n.liveSessionCount(running)}',
                  );
                }
                final session = _sessions![index - 1];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    key: ValueKey('session-${session.sessionId}'),
                    leading: _sessionLeading(session),
                    title: Text(session.localizedDisplayName(l10n)),
                    subtitle: Text(session.shortId),
                    onTap: _busy ? null : () => _open(session),
                    trailing: _sessionTrailing(session),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<SessionSummary> get _filteredSessions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _sessions ?? const [];
    return (_sessions ?? const <SessionSummary>[])
        .where(
          (session) =>
              session
                  .localizedDisplayName(context.l10n)
                  .toLowerCase()
                  .contains(query) ||
              session.sessionId.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Widget _sessionLeading(SessionSummary session) {
    if (_openingSessionId == session.sessionId ||
        _removingSessionId == session.sessionId) {
      return const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      session.runtimeState == RuntimeState.running
          ? Icons.motion_photos_on_outlined
          : Icons.chat_bubble_outline,
    );
  }

  Widget? _sessionTrailing(SessionSummary session) {
    if (_sessionsGateway == null || _busy) return null;
    return IconButton(
      onPressed: () => _remove(session),
      tooltip: context.l10n.deletePermanently,
      icon: const Icon(Icons.delete_outline),
    );
  }
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

class _SessionError extends StatelessWidget {
  const _SessionError({required this.problem, required this.onRetry});

  final TsPhoneProblem problem;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => TsEmptyState(
    icon: Icons.cloud_off_outlined,
    title: context.l10n.loadSessionsFailed,
    message: problem.localizedMessage(context.l10n),
    action: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: Text(context.l10n.retry),
    ),
  );
}
