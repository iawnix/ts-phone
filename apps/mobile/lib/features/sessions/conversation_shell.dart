import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ts_phone/theme/app_icons.dart';

import '../../data/app_server_gateway.dart';
import '../../data/host_gateway.dart';
import '../../data/settings_store.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/presentation.dart';
import '../chat/chat_page.dart';
import '../chat/chat_view_memory.dart';
import 'context_switcher.dart';
import 'session_list_page.dart';

/// One Host owns the session directory for every installed workspace.
class ConversationShell extends StatefulWidget {
  const ConversationShell({
    super.key,
    required this.settings,
    required this.onOpenSettings,
    this.selectionStore,
    this.gatewayBuilder,
  });

  final ConnectionSettings settings;
  final VoidCallback onOpenSettings;
  final ConversationSelectionStore? selectionStore;
  final TsPhoneGateway Function(ConnectionSettings settings)? gatewayBuilder;

  @override
  State<ConversationShell> createState() => _ConversationShellState();
}

class _ConversationShellState extends State<ConversationShell>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _memory = ConversationMemory();
  late final TsPhoneGateway _api;
  List<WorkspaceSummary>? _workspaces;
  WorkspaceSummary? _workspace;
  TsPhoneProblem? _workspaceProblem;
  SessionSummary? _session;
  List<SessionSummary>? _sessions;
  bool _creating = false;
  bool _initializing = true;
  bool _showInitialContext = false;
  bool _refreshingWorkspaces = false;
  Timer? _workspaceRefreshTimer;
  int _generation = 0;
  int _sidebarRevision = 0;
  int _selectionEpoch = 0;

  LocalKey get _chatKey =>
      ValueKey(('chat', _workspace?.id, _session?.sessionId, _generation));

  AppServerSessionGateway? get _management =>
      _api is AppServerSessionGateway ? _api as AppServerSessionGateway : null;

  AppServerWorkspaceGateway? get _workspaceManagement =>
      _api is AppServerWorkspaceGateway
      ? _api as AppServerWorkspaceGateway
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api =
        widget.gatewayBuilder?.call(widget.settings) ??
        HostGateway(widget.settings);
    unawaited(_loadWorkspaces(restoreRecent: true));
    _workspaceRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_session == null && mounted) {
        unawaited(_loadWorkspaces());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workspaceRefreshTimer?.cancel();
    _api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadWorkspaces());
    }
  }

  void _showDirectory() {
    _scaffold.currentState?.closeDrawer();
    _selectionEpoch += 1;
    setState(() {
      _generation += 1;
      _session = null;
      _showInitialContext = _workspaces?.isNotEmpty == true;
    });
  }

  Future<void> _loadWorkspaces({bool restoreRecent = false}) async {
    if (_refreshingWorkspaces) return;
    _refreshingWorkspaces = true;
    final hadWorkspaces = _workspaces != null;
    final selectionEpoch = _selectionEpoch;
    try {
      final workspaces = await _api.listWorkspaces();
      if (!mounted) return;
      final existingWorkspace = _workspace;
      final selectedWorkspace =
          existingWorkspace != null &&
              workspaces.any((value) => value.id == existingWorkspace.id)
          ? workspaces.firstWhere((value) => value.id == existingWorkspace.id)
          : workspaces.length == 1
          ? workspaces.single
          : workspaces.firstOrNull;
      setState(() {
        _workspaces = workspaces;
        _workspace = selectedWorkspace;
        _workspaceProblem = null;
      });
      if (restoreRecent) {
        final restored = await _restoreRecentConversation(
          workspaces,
          selectionEpoch,
        );
        if (!restored && mounted && workspaces.isNotEmpty) {
          _scheduleInitialContext(selectionEpoch);
        }
      }
      if (mounted) setState(() => _initializing = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _initializing = false);
      final problem = describeTsPhoneProblem(error);
      setState(() => _workspaceProblem = problem);
      if (hadWorkspaces) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(problem.localizedMessage(context.l10n))),
          );
      }
    } finally {
      _refreshingWorkspaces = false;
    }
  }

  Future<bool> _restoreRecentConversation(
    List<WorkspaceSummary> workspaces,
    int selectionEpoch,
  ) async {
    final store = widget.selectionStore;
    (String, String)? recent;
    if (store != null) {
      try {
        recent = await store.loadConversation(widget.settings.serverUrl);
      } on Object {
        recent = null;
      }
    }
    if (!mounted || selectionEpoch != _selectionEpoch) {
      return false;
    }
    if (recent != null) {
      WorkspaceSummary? workspace;
      for (final candidate in workspaces) {
        if (candidate.id == recent.$1) {
          workspace = candidate;
          break;
        }
      }
      // Versions before the workspace-aware preference stored serverId here.
      // A single workspace lets us recover that preference without guessing
      // when several projects are available.
      if (workspace == null &&
          workspaces.length == 1 &&
          recent.$1 == widget.settings.serverId) {
        workspace = workspaces.single;
      }
      if (workspace != null) {
        try {
          final sessions = await _api.listSessions(workspace.id);
          if (!mounted || selectionEpoch != _selectionEpoch) return false;
          final session = sessions
              .where((candidate) => candidate.sessionId == recent!.$2)
              .firstOrNull;
          if (session != null) {
            setState(() {
              _workspace = workspace;
              _sessions = sessions;
              _session = session;
              _generation += 1;
              _sidebarRevision += 1;
              _selectionEpoch += 1;
            });
            return true;
          }
        } on Object {
          // A missing saved session should fall through to the latest one.
        }
      }
    }
    return _restoreLatestConversation(workspaces, selectionEpoch);
  }

  Future<bool> _restoreLatestConversation(
    List<WorkspaceSummary> workspaces,
    int selectionEpoch,
  ) async {
    if (!mounted || selectionEpoch != _selectionEpoch) return false;
    final candidates = <(WorkspaceSummary, List<SessionSummary>)>[];
    for (final workspace in workspaces) {
      try {
        final sessions = await _api.listSessions(workspace.id);
        if (sessions.isNotEmpty) candidates.add((workspace, sessions));
      } on Object {
        // One unavailable project should not hide sessions from the others.
      }
      if (!mounted || selectionEpoch != _selectionEpoch) return false;
    }
    if (candidates.isEmpty) return false;
    (WorkspaceSummary, SessionSummary)? latest;
    for (final (workspace, sessions) in candidates) {
      for (final session in sessions) {
        final current = latest?.$2;
        final currentUpdated = current?.updatedAt;
        final sessionUpdated = session.updatedAt;
        if (latest == null ||
            (sessionUpdated != null &&
                (currentUpdated == null ||
                    sessionUpdated.isAfter(currentUpdated)))) {
          latest = (workspace, session);
        }
      }
    }
    if (latest == null || !mounted || selectionEpoch != _selectionEpoch) {
      return false;
    }
    final (workspace, session) = latest;
    final sessions = candidates
        .firstWhere((candidate) => candidate.$1.id == workspace.id)
        .$2;
    setState(() {
      _workspace = workspace;
      _sessions = sessions;
      _session = session;
      _generation += 1;
      _sidebarRevision += 1;
      _selectionEpoch += 1;
    });
    return true;
  }

  void _scheduleInitialContext(int selectionEpoch) {
    if (selectionEpoch != _selectionEpoch || _session != null) return;
    setState(() => _showInitialContext = true);
  }

  void _selectWorkspace(WorkspaceSummary workspace) {
    _scaffold.currentState?.closeDrawer();
    _selectionEpoch += 1;
    setState(() {
      _workspace = workspace;
      _session = null;
      _sessions = null;
      _generation += 1;
      _showInitialContext = true;
    });
  }

  void _selectSession(SessionSummary session) {
    final workspace = _workspace;
    if (workspace == null) return;
    _selectContextSession(workspace, session);
  }

  void _selectContextSession(
    WorkspaceSummary workspace,
    SessionSummary session,
  ) {
    _scaffold.currentState?.closeDrawer();
    _selectionEpoch += 1;
    final workspaceChanged = _workspace?.id != workspace.id;
    setState(() {
      _workspace = workspace;
      if (workspaceChanged) _sessions = null;
      _generation += 1;
      _session = session;
      _showInitialContext = false;
    });
    unawaited(_remember(workspace.id, session.sessionId));
  }

  Future<void> _remember(String workspace, String session) async {
    try {
      await widget.selectionStore?.saveConversation(
        widget.settings.serverUrl,
        workspace,
        session,
      );
    } on Object {
      // Recent selection is a presentation preference, never session state.
    }
  }

  Future<void> _newSession() async {
    final management = _management;
    if (_creating || management == null) return;
    _scaffold.currentState?.closeDrawer();
    final generation = _generation;
    setState(() => _creating = true);
    try {
      final workspace = _workspace;
      if (workspace == null) return;
      final session = await management.createWorkspaceSession(workspace.id);
      if (!mounted) return;
      setState(() {
        _sessions = [
          session,
          ...?_sessions?.where((value) => value.sessionId != session.sessionId),
        ];
        _sidebarRevision += 1;
      });
      if (generation == _generation) _selectSession(session);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              describeTsPhoneProblem(error).localizedMessage(context.l10n),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<List<SessionSummary>> _loadSessionsForContext(
    WorkspaceSummary workspace,
  ) => _api.listSessions(workspace.id);

  Future<SessionSummary?> _createSessionForContext(
    WorkspaceSummary workspace,
  ) async {
    final management = _management;
    if (_creating || management == null) return null;
    setState(() => _creating = true);
    try {
      final session = await management.createWorkspaceSession(workspace.id);
      if (!mounted) return session;
      if (_workspace?.id == workspace.id) {
        setState(() {
          _sessions = [
            session,
            ...?_sessions?.where(
              (value) => value.sessionId != session.sessionId,
            ),
          ];
          _sidebarRevision += 1;
        });
      }
      return session;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              describeTsPhoneProblem(error).localizedMessage(context.l10n),
            ),
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showContextSwitcher() async {
    if (_workspaces == null) await _loadWorkspaces();
    if (!mounted) return;
    final workspaces = _workspaces;
    final workspace = _workspace ?? workspaces?.firstOrNull;
    if (workspaces == null || workspace == null || workspaces.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: TsPhoneMotion.resolveAnimationStyle(context),
      builder: (context) => ContextSwitcherSheet(
        workspaces: workspaces,
        selectedWorkspace: workspace,
        selectedSession: _session,
        initialSessions: _sessions,
        loadSessions: _loadSessionsForContext,
        onSessionSelected: _selectContextSession,
        onCreateSession: managementAvailable ? _createSessionForContext : null,
        onCreateWorkspace: _workspaceManagement == null
            ? null
            : () => _newWorkspace(select: false),
      ),
    );
  }

  Future<WorkspaceSummary?> _newWorkspace({bool select = true}) async {
    final management = _workspaceManagement;
    if (management == null) return null;
    final controller = TextEditingController();
    final workspaceId = await showDialog<String>(
      context: context,
      animationStyle: TsPhoneMotion.resolveAnimationStyle(context),
      builder: (context) => AlertDialog(
        title: Text(context.l10n.newProject),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: context.l10n.projectName),
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.l10n.createProject),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = workspaceId?.trim() ?? '';
    if (normalized.isEmpty) return null;
    try {
      final created = await management.createWorkspace(normalized);
      await _loadWorkspaces();
      if (select && mounted) _selectWorkspace(created);
      return created;
    } on Object catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeTsPhoneProblem(error).localizedMessage(context.l10n),
          ),
        ),
      );
      return null;
    }
  }

  Widget _sessionList({required bool sidebar}) {
    final workspace = _workspace;
    if (workspace == null) return _workspaceDirectory(sidebar: sidebar);
    final revision = _sidebarRevision;
    final selectedId = _session?.sessionId;
    return SessionListPage(
      key: ValueKey((workspace.id, sidebar)),
      settings: widget.settings,
      workspace: workspace,
      initialSessions: _sessions,
      gatewayBuilder: widget.gatewayBuilder,
      sidebar: sidebar,
      onOpenSettings: widget.onOpenSettings,
      selectedSessionId: selectedId,
      refreshToken: revision,
      onSelected: _selectSession,
      onSessionsChanged: (sessions) {
        if (!mounted || _creating || revision != _sidebarRevision) return;
        setState(() {
          _sessions = sessions;
          final selected = sessions
              .where((value) => value.sessionId == selectedId)
              .firstOrNull;
          _session = selected;
        });
      },
      onCreateSession: managementAvailable ? _newSession : null,
      creatingSession: _creating,
      onBack: _showDirectory,
      sidebarHeader: sidebar
          ? ListTile(
              key: const ValueKey('sidebar-directory'),
              leading: const Icon(AppIcons.forum_outlined, size: 22),
              title: Text(context.l10n.sessions),
              onTap: _showDirectory,
            )
          : null,
      sidebarFooter: sidebar
          ? ListTile(
              leading: const Icon(AppIcons.settings_outlined, size: 22),
              title: Text(context.l10n.settings),
              onTap: widget.onOpenSettings,
            )
          : null,
    );
  }

  Widget _initialContext() {
    final workspaces = _workspaces;
    final workspace = _workspace ?? workspaces?.firstOrNull;
    if (workspaces == null || workspace == null || workspaces.isEmpty) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: TsGlassAppBar(
        title: Text(context.l10n.workspaces),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('initial-context-menu'),
            tooltip: context.l10n.moreActions,
            icon: const Icon(AppIcons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'settings') widget.onOpenSettings();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(AppIcons.settings_outlined, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(context.l10n.settings)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ContextSwitcherSheet(
        workspaces: workspaces,
        selectedWorkspace: workspace,
        selectedSession: _session,
        initialSessions: _sessions,
        loadSessions: _loadSessionsForContext,
        onSessionSelected: _selectContextSession,
        onCreateSession: managementAvailable ? _createSessionForContext : null,
        onCreateWorkspace: _workspaceManagement == null
            ? null
            : () => _newWorkspace(select: false),
        dismissOnSessionSelected: false,
        embedded: true,
      ),
    );
  }

  bool get managementAvailable => _management != null;

  Widget _workspaceDirectory({required bool sidebar}) {
    final workspaces = _workspaces;
    return Scaffold(
      appBar: sidebar
          ? null
          : TsGlassAppBar(
              title: Text(context.l10n.workspaces),
              actions: [
                if (_workspaceManagement != null)
                  IconButton(
                    onPressed: () => unawaited(_newWorkspace()),
                    tooltip: context.l10n.newProject,
                    icon: const Icon(AppIcons.create_new_folder_outlined),
                  ),
                PopupMenuButton<String>(
                  key: const ValueKey('workspace-menu'),
                  tooltip: context.l10n.moreActions,
                  icon: const Icon(AppIcons.more_horiz_rounded),
                  onSelected: (value) {
                    if (value == 'settings') widget.onOpenSettings();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'settings',
                      child: Row(
                        children: [
                          const Icon(AppIcons.settings_outlined, size: 20),
                          const SizedBox(width: 12),
                          Flexible(child: Text(context.l10n.settings)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: workspaces == null
          ? _workspaceProblem == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _workspaceProblem!.localizedMessage(context.l10n),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => unawaited(_loadWorkspaces()),
                            icon: const Icon(AppIcons.refresh),
                            label: Text(context.l10n.refreshSessions),
                          ),
                        ],
                      ),
                    ),
                  )
          : RefreshIndicator(
              onRefresh: _loadWorkspaces,
              child: workspaces.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.noWorkspacesMessage,
                                textAlign: TextAlign.center,
                              ),
                              if (_workspaceManagement != null) ...[
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => unawaited(_newWorkspace()),
                                  icon: const Icon(
                                    AppIcons.create_new_folder_outlined,
                                  ),
                                  label: Text(context.l10n.newProject),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: workspaces.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final workspace = workspaces[index];
                        final activity = workspace.liveSessionCount > 0
                            ? context.l10n.liveSessionCount(
                                workspace.liveSessionCount,
                              )
                            : context.l10n.sessionCount(workspace.sessionCount);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: TsPhoneSpacing.large,
                            vertical: TsPhoneSpacing.xSmall,
                          ),
                          leading: const Icon(AppIcons.folder_outlined),
                          title: Text(workspace.name),
                          subtitle: Text(
                            activity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(AppIcons.chevron_right),
                          onTap: () => _selectWorkspace(workspace),
                        );
                      },
                    ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return NavigatorPopHandler(
      enabled: _session != null,
      onPopWithResult: (result) => _navigator.currentState?.maybePop(result),
      child: Navigator(
        key: _navigator,
        pages: [
          TsAdaptivePage<void>(
            key: const ValueKey('sessions'),
            child: _showInitialContext
                ? _initialContext()
                : _sessionList(sidebar: false),
          ),
          if (_session != null)
            TsAdaptivePage<void>(key: _chatKey, child: _chat()),
        ],
        onDidRemovePage: (page) {
          if (mounted && _session != null && page.key == _chatKey) {
            _showDirectory();
          }
        },
      ),
    );
  }

  Widget _chat() {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final session = _session!;
    final content = ChatPage(
      key: ValueKey((_workspace!.id, session.sessionId, _generation)),
      settings: widget.settings,
      workspace: _workspace!,
      session: session,
      onOpenSession: _selectSession,
      gatewayFactory: widget.gatewayBuilder == null
          ? null
          : () => widget.gatewayBuilder!(widget.settings),
      memory: _memory.view(_workspace!.id, session.sessionId),
      onOpenContext: wide ? null : () => unawaited(_showContextSwitcher()),
      embedded: true,
    );
    return Scaffold(
      key: _scaffold,
      body: wide
          ? Row(
              children: [
                SizedBox(width: 300, child: _sessionList(sidebar: true)),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
