import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../models/workspace.dart';
import '../../navigation/adaptive_page_route.dart';
import '../chat/chat_page.dart';
import '../chat/chat_view_memory.dart';
import '../workspaces/workspace_list_page.dart';
import 'session_list_page.dart';

/// Navigation is explicit. Reading a list or opening history never starts a worker.
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
  final TsPhoneGatewayBuilder? gatewayBuilder;

  @override
  State<ConversationShell> createState() => _ConversationShellState();
}

class _ConversationShellState extends State<ConversationShell> {
  final _navigator = GlobalKey<NavigatorState>();
  var _scaffold = GlobalKey<ScaffoldState>();
  final _memory = ConversationMemory();
  late final TsPhoneGateway _api;
  WorkspaceSummary? _workspace;
  SessionSummary? _session;
  List<SessionSummary>? _sessions;
  bool _creating = false;
  int _generation = 0;
  int _sidebarRevision = 0;
  int _navigationId = 0;
  int _homeRevision = 0;
  bool _fromProjectList = false;

  LocalKey get _listKey => ValueKey(('sessions', _navigationId));
  LocalKey get _chatKey => ValueKey(('chat', _navigationId));

  TsPhoneManagementGateway? get _management => _api is TsPhoneManagementGateway
      ? _api as TsPhoneManagementGateway
      : null;

  @override
  void initState() {
    super.initState();
    _api =
        widget.gatewayBuilder?.call(widget.settings) ??
        TsPhoneApi(widget.settings);
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _goHome() {
    _scaffold.currentState?.closeDrawer();
    setState(() {
      _generation += 1;
      _workspace = null;
      _session = null;
      _sessions = null;
      _fromProjectList = false;
      _homeRevision++;
    });
  }

  void _selectWorkspace(WorkspaceSummary workspace) {
    setState(() {
      _generation += 1;
      _workspace = workspace;
      _session = null;
      _sessions = null;
      _fromProjectList = true;
      _navigationId++;
      _scaffold = GlobalKey<ScaffoldState>();
    });
  }

  void _selectSession(SessionSummary session) {
    _scaffold.currentState?.closeDrawer();
    setState(() {
      _generation += 1;
      _session = session;
    });
    unawaited(_remember(_workspace!.id, session.sessionId));
  }

  void _openRecent(WorkspaceSummary workspace, SessionSummary session) {
    _selectWorkspace(workspace);
    _fromProjectList = false;
    _selectSession(session);
  }

  Future<void> _remember(String workspace, String session) async {
    try {
      await widget.selectionStore?.saveConversation(
        widget.settings.serverUrl,
        workspace,
        session,
      );
    } on Object {
      // An optional recent-selection preference must not block navigation.
    }
  }

  Future<void> _newSession() async {
    final workspace = _workspace;
    final management = _management;
    if (_creating || workspace == null || management == null) return;
    _scaffold.currentState?.closeDrawer();
    final generation = _generation;
    setState(() => _creating = true);
    try {
      final session = await management.createSession(
        workspace.id,
        accessMode: SessionAccessMode.controller,
      );
      if (!mounted || _workspace?.id != workspace.id) return;
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
    final generation = _generation;
    final revision = _sidebarRevision;
    final selectedId = _session?.sessionId;
    return SessionListPage(
      key: ValueKey((_workspace!.id, sidebar)),
      settings: widget.settings,
      workspace: _workspace!,
      initialSessions: _sessions,
      gatewayBuilder: widget.gatewayBuilder,
      sidebar: sidebar,
      onBack: _goHome,
      selectedSessionId: selectedId,
      refreshToken: revision,
      onSelected: _selectSession,
      onSessionsChanged: (sessions) {
        if (!mounted ||
            _creating ||
            generation != _generation ||
            revision != _sidebarRevision ||
            selectedId != _session?.sessionId) {
          return;
        }
        setState(() {
          _sessions = sessions;
          // A removed/archived selection returns to the list, never another chat.
          final selected = sessions
              .where((value) => value.sessionId == selectedId)
              .firstOrNull;
          if (_session != null && selected == null) _fromProjectList = true;
          _session = selected;
        });
      },
      onCreateSession: _management == null ? null : _newSession,
      creatingSession: _creating,
      sidebarHeader: sidebar
          ? ListTile(
              key: const ValueKey('sidebar-home'),
              leading: const Icon(Icons.arrow_back, size: 22),
              title: Text(context.l10n.home),
              onTap: _goHome,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      enabled: _workspace != null,
      onPopWithResult: (result) => _navigator.currentState?.maybePop(result),
      child: Navigator(
        key: _navigator,
        pages: [
          TsAdaptivePage<void>(
            key: const ValueKey('home'),
            child: WorkspaceListPage(
              key: ValueKey(('home-content', _homeRevision)),
              settings: widget.settings,
              onOpenSettings: widget.onOpenSettings,
              gatewayBuilder: widget.gatewayBuilder,
              selectionStore: widget.selectionStore,
              onSelected: _selectWorkspace,
              onSessionSelected: _openRecent,
            ),
          ),
          if (_workspace != null && (_fromProjectList || _session == null))
            TsAdaptivePage<void>(
              key: _listKey,
              child: _sessionList(sidebar: false),
            ),
          if (_workspace != null && _session != null)
            TsAdaptivePage<void>(key: _chatKey, child: _chat()),
        ],
        onDidRemovePage: (page) {
          if (!mounted) return;
          if (_session != null && page.key == _chatKey) {
            if (!_fromProjectList) {
              _goHome();
            } else {
              setState(() {
                _generation++;
                _session = null;
              });
            }
          } else if (_workspace != null && page.key == _listKey) {
            _goHome();
          }
        },
      ),
    );
  }

  Widget _chat() {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final session = _session!;
    final content = ChatPage(
      key: ValueKey((_workspace!.id, session.sessionId)),
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
