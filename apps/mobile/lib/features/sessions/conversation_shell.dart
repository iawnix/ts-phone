import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_server_gateway.dart';
import '../../data/settings_store.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../chat/chat_page.dart';
import '../chat/chat_view_memory.dart';
import 'session_list_page.dart';

/// One App Server owns one session directory; navigation starts at that directory.
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
  late final WorkspaceSummary _server;
  SessionSummary? _session;
  List<SessionSummary>? _sessions;
  bool _creating = false;
  int _generation = 0;
  int _sidebarRevision = 0;

  LocalKey get _chatKey => ValueKey(('chat', _session?.sessionId));

  AppServerSessionGateway? get _management =>
      _api is AppServerSessionGateway ? _api as AppServerSessionGateway : null;

  @override
  void initState() {
    super.initState();
    _api =
        widget.gatewayBuilder?.call(widget.settings) ??
        PiAppServerGateway(widget.settings);
    _server = WorkspaceSummary(
      id: appServerWorkspaceId,
      name: 'App Server',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      liveSessionCount: 0,
      sessionCount: 0,
    );
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
      final session = await management.createSession();
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

  Widget _sessionList({required bool sidebar}) {
    final revision = _sidebarRevision;
    final selectedId = _session?.sessionId;
    return SessionListPage(
      key: ValueKey((appServerWorkspaceId, sidebar)),
      settings: widget.settings,
      workspace: _server,
      initialSessions: _sessions,
      gatewayBuilder: widget.gatewayBuilder,
      sidebar: sidebar,
      onBack: sidebar ? _showDirectory : null,
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
      key: ValueKey((appServerWorkspaceId, session.sessionId, _generation)),
      settings: widget.settings,
      workspace: _server,
      session: session,
      onOpenSession: _selectSession,
      gatewayFactory: widget.gatewayBuilder == null
          ? null
          : () => widget.gatewayBuilder!(widget.settings),
      memory: _memory.view(appServerWorkspaceId, session.sessionId),
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
