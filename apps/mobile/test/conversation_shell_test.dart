import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/settings_store.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/data/app_server_gateway.dart';
import 'package:ts_phone/features/sessions/conversation_shell.dart';
import 'package:ts_phone/features/sessions/context_switcher.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

final settings = ConnectionSettings(
  serverUrl: 'https://link.example.test',
  serverId: '123e4567-e89b-42d3-a456-426614174000',
  deviceId: '223e4567-e89b-42d3-a456-426614174000',
  token: 'tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

final appServer = WorkspaceSummary(
  id: appServerWorkspaceId,
  name: 'App Server',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  liveSessionCount: 2,
  sessionCount: 2,
);

SessionSummary session(String id) => SessionSummary(
  sessionId: id,
  sessionRevision: 'pi-app-server-8-123e4567-e89b-42d3-a456-426614174000-$id',
  sessionName: 'Session $id',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  historyAvailable: true,
  canPrompt: true,
  capabilities: const {'command.model'},
);

class ConversationGateway implements TsPhoneGateway, AppServerSessionGateway {
  List<WorkspaceSummary> workspaces = [appServer];
  List<SessionSummary> sessions = [session('one'), session('two')];
  int created = 0;

  @override
  Future<Map<String, Object?>> version() async => const {
    'apiVersion': 'pi-app-server/8',
    'serviceVersion': 'Pi App Server',
  };

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaces;

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    expect(workspaceId, appServerWorkspaceId);
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
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) async => TsPhoneMessageSnapshot(
    sessionId: sessionId,
    sessionRevision: session(sessionId).sessionRevision,
    messages: const [],
    messageIds: const [],
    lastEventId: 'pi-0',
  );

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) => throw const TsPhoneApiException('timeline unsupported');

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
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async {}

  @override
  Stream<TsPhoneEvent> events(
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
  theme: TsPhoneTheme.light(),
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
  testWidgets('opens the latest session without recent selection history', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.text('Session one'), findsOneWidget);
    expect(find.byType(ContextSwitcherSheet), findsNothing);
    expect(find.byType(ConversationShell), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey<String>('chat-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('context-new-session')));
    await tester.pumpAndSettle();
    expect(gateway.created, 1);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(store.savedWorkspace, appServerWorkspaceId);
    expect(store.savedSession, 'new-1');
  });

  testWidgets('restores the recent session directly into chat', (tester) async {
    final gateway = ConversationGateway();
    final store = _SelectionStore(recent: (appServerWorkspaceId, 'one'));
    await tester.pumpWidget(shellApp(gateway, selectionStore: store));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(ContextSwitcherSheet), findsNothing);
  });
}
