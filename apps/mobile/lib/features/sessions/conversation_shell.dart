import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_server_gateway.dart';
import '../../data/host_gateway.dart';
import '../../data/settings_store.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../chat/chat_page.dart';
import '../chat/chat_view_memory.dart';
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

class _ConversationShellState extends State<ConversationShell> {
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
  int _generation = 0;
  int _sidebarRevision = 0;

  LocalKey get _chatKey => ValueKey(('chat', _session?.sessionId));

  AppServerSessionGateway? get _management =>
      _api is AppServerSessionGateway ? _api as AppServerSessionGateway : null;

  AppServerWorkspaceGateway? get _workspaceManagement =>
      _api is AppServerWorkspaceGateway
      ? _api as AppServerWorkspaceGateway
      : null;

  @override
  void initState() {
    super.initState();
    _api =
        widget.gatewayBuilder?.call(widget.settings) ??
        HostGateway(widget.settings);
    unawaited(_loadWorkspaces());
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _showDirectory() {
    _scaffold.currentState?.closeDrawer();
    setState(() {
      _generation += 1;
      _session = null;
      _workspace = null;
      _sessions = null;
    });
  }

  Future<void> _loadWorkspaces() async {
    try {
      final workspaces = await _api.listWorkspaces();
      if (!mounted) return;
      setState(() {
        _workspaces = workspaces;
        _workspace = workspaces.length == 1 ? workspaces.single : null;
        _workspaceProblem = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _workspaceProblem = describeTsPhoneProblem(error));
    }
  }

  void _selectWorkspace(WorkspaceSummary workspace) {
    _scaffold.currentState?.closeDrawer();
    setState(() {
      _workspace = workspace;
      _session = null;
      _sessions = null;
      _generation += 1;
    });
  }

  void _selectSession(SessionSummary session) {
    _scaffold.currentState?.closeDrawer();
    setState(() {
      _generation += 1;
      _session = session;
    });
    unawaited(_remember(session.sessionId));
  }

  Future<void> _remember(String session) async {
    try {
      await widget.selectionStore?.saveConversation(
        widget.settings.serverUrl,
        widget.settings.serverId,
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

  Future<void> _newWorkspace() async {
    final management = _workspaceManagement;
    if (management == null) return;
    final controller = TextEditingController();
    final workspaceId = await showDialog<String>(
      context: context,
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
    if (normalized.isEmpty) return;
    try {
      final created = await management.createWorkspace(normalized);
      await _loadWorkspaces();
      if (mounted) _selectWorkspace(created);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeTsPhoneProblem(error).localizedMessage(context.l10n),
          ),
        ),
      );
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
              leading: const Icon(Icons.forum_outlined, size: 22),
              title: Text(context.l10n.sessions),
              onTap: _showDirectory,
            )
          : null,
      sidebarFooter: sidebar
          ? ListTile(
              leading: const Icon(Icons.settings_outlined, size: 22),
              title: Text(context.l10n.settings),
              onTap: widget.onOpenSettings,
            )
          : null,
    );
  }

  bool get managementAvailable => _management != null;

  Widget _workspaceDirectory({required bool sidebar}) {
    final workspaces = _workspaces;
    return Scaffold(
      appBar: sidebar
          ? null
          : AppBar(
              title: Text(context.l10n.projectViews),
              actions: [
                IconButton(
                  onPressed: () => unawaited(_loadWorkspaces()),
                  tooltip: context.l10n.refreshSessions,
                  icon: const Icon(Icons.refresh),
                ),
                if (_workspaceManagement != null)
                  IconButton(
                    onPressed: () => unawaited(_newWorkspace()),
                    tooltip: context.l10n.newProject,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                IconButton(
                  onPressed: widget.onOpenSettings,
                  tooltip: context.l10n.settings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
      body: workspaces == null
          ? _workspaceProblem == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _workspaceProblem!.localizedMessage(context.l10n),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
          : workspaces.isEmpty
          ? Center(
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
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: Text(context.l10n.newProject),
                    ),
                  ],
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: workspaces.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final workspace = workspaces[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(workspace.name),
                    subtitle: Text(
                      context.l10n.sessionCount(workspace.sessionCount),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _selectWorkspace(workspace),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      enabled: _session != null,
      onPopWithResult: (result) => _navigator.currentState?.maybePop(result),
      child: Navigator(
        key: _navigator,
        pages: [
          TsAdaptivePage<void>(
            key: const ValueKey('sessions'),
            child: _sessionList(sidebar: false),
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
      onOpenNavigation: wide
          ? null
          : () => _scaffold.currentState?.openDrawer(),
      embedded: true,
    );
    return Scaffold(
      key: _scaffold,
      drawerEnableOpenDragGesture: false,
      drawer: wide
          ? null
          : Drawer(
              width: MediaQuery.sizeOf(context).width.clamp(0, 360) - 32,
              shape: const RoundedRectangleBorder(),
              child: _sessionList(sidebar: true),
            ),
      onDrawerChanged: (opened) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (opened) setState(() => _sidebarRevision += 1);
      },
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
