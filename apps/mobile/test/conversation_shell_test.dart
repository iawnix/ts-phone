import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corhub/data/settings_store.dart';
import 'package:corhub/data/corhub_api.dart';
import 'package:corhub/data/session_gateway.dart';
import 'package:corhub/features/sessions/conversation_shell.dart';
import 'package:corhub/features/sessions/context_switcher.dart';
import 'package:corhub/features/chat/chat_page.dart';
import 'package:corhub/l10n/app_localizations.dart';
import 'package:corhub/models/connection_settings.dart';
import 'package:corhub/models/workspace.dart';
import 'package:corhub/theme/corhub_theme.dart';

final settings = ConnectionSettings(
  serverUrl: 'https://link.example.test',
  serverId: '123e4567-e89b-42d3-a456-426614174000',
  deviceId: '223e4567-e89b-42d3-a456-426614174000',
  token: 'cad_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

final appServer = WorkspaceSummary(
  id: 'ts_001',
  name: 'App Server',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  liveSessionCount: 2,
  sessionCount: 2,
);

SessionSummary session(String id) => SessionSummary(
  sessionId: id,
  sessionRevision: 'host-$id',
  sessionName: 'Session $id',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  historyAvailable: true,
  canPrompt: true,
  capabilities: const {'command.model'},
);

class ConversationGateway implements CorHubGateway, SessionManagementGateway {
  List<WorkspaceSummary> workspaces = [appServer];
  List<SessionSummary> sessions = [session('one'), session('two')];
  int created = 0;

  @override
  Future<Map<String, Object?>> version() async => const {
    'apiVersion': 'coragent-host/2',
    'serviceVersion': 'Pi App Server',
  };

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaces;

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    expect(workspaceId, 'ts_001');
    return sessions;
  }

  @override
  Future<SessionSummary> createSession() async {
    created += 1;
    final value = session('new-$created');
    sessions = [...sessions, value];
    return value;
  }

  @override
  Future<void> removeSession(String sessionId) async {
    sessions = sessions.where((value) => value.sessionId != sessionId).toList();
  }

  @override
  Future<CorHubMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId,
  ) async => CorHubMessageSnapshot(
    sessionId: sessionId,
    sessionRevision: session(sessionId).sessionRevision,
    messages: const [],
    messageIds: const [],
    lastEventId: 'pi-0',
  );

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) async {}

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) async {}

  @override
  Stream<CorHubEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) => const Stream.empty();

  @override
  void close() {}
}

Widget shellApp(
  ConversationGateway gateway, {
  ConversationSelectionStore? selectionStore,
}) => MaterialApp(
  theme: CorHubTheme.light(),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: ConversationShell(
    settings: settings,
    onOpenSettings: () {},
    gatewayBuilder: (_) => gateway,
    selectionStore: selectionStore ?? _SelectionStore(),
  ),
);

class _SelectionStore implements ConversationSelectionStore {
  _SelectionStore({this.recent});

  final (String, String)? recent;
  String? savedWorkspace;
  String? savedSession;

  @override
  Future<(String, String)?> loadConversation(String endpoint) async => recent;

  @override
  Future<void> saveConversation(
    String endpoint,
    String workspace,
    String session,
  ) async {
    savedWorkspace = workspace;
    savedSession = session;
  }
}

void loadPreviewFonts() {}

void main() {
  testWidgets('opens the project directory without recent selection history', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    expect(find.byType(ContextSwitcherSheet), findsOneWidget);
    expect(find.byType(ChatPage), findsNothing);
    expect(find.text('Session one'), findsOneWidget);
    expect(find.byType(ConversationShell), findsOneWidget);
  });

  testWidgets('exposes Settings directly from the project directory', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    var settingsOpened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: CorHubTheme.light(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ConversationShell(
          settings: settings,
          onOpenSettings: () => settingsOpened += 1,
          gatewayBuilder: (_) => gateway,
          selectionStore: _SelectionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('initial-context-settings')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('initial-context-menu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('initial-context-settings')));
    expect(settingsOpened, 1);
  });

  testWidgets('refreshes the project directory when the app resumes', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    gateway.sessions = [];
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();

    gateway.workspaces = [
      appServer,
      const WorkspaceSummary(
        id: 'project-b',
        name: 'Project B',
        runtimeState: RuntimeState.idle,
        isStreaming: false,
        liveSessionCount: 0,
        sessionCount: 0,
      ),
    ];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Project B'), findsOneWidget);
  });

  testWidgets('creates and opens a native App Server session', (tester) async {
    final gateway = ConversationGateway();
    final store = _SelectionStore();
    await tester.pumpWidget(shellApp(gateway, selectionStore: store));
    await tester.pumpAndSettle();
    expect(find.byType(ContextSwitcherSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('context-new-session')));
    await tester.pumpAndSettle();
    expect(gateway.created, 1);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(store.savedWorkspace, 'ts_001');
    expect(store.savedSession, 'new-1');
  });

  testWidgets('keeps the chat header passive and hides manual sync', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Session one'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-session-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-session-details')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-menu')), findsNothing);
    expect(find.text('Sync messages'), findsNothing);
  });

  testWidgets(
    'keeps the project directory on cold start with a recent session',
    (tester) async {
      final gateway = ConversationGateway();
      final store = _SelectionStore(recent: ('ts_001', 'one'));
      await tester.pumpWidget(shellApp(gateway, selectionStore: store));
      await tester.pumpAndSettle();
      expect(find.byType(ContextSwitcherSheet), findsOneWidget);
      expect(find.byType(ChatPage), findsNothing);
      expect(find.text('App Server'), findsOneWidget);
    },
  );
}
