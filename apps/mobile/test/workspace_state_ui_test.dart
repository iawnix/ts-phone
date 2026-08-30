import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/sessions/session_list_page.dart';
import 'package:ts_phone/features/workspaces/workspace_list_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/widgets/markdown_message.dart';
import 'package:ts_phone/widgets/presentation.dart';

final _settings = ConnectionSettings(
  serverUrl: 'https://tsphone.example.test',
  token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

const controllerSession = SessionSummary(
  sessionId: 'session-test',
  sessionRevision: '11111111-1111-4111-8111-111111111111',
  sessionName: '测试会话',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
);

const offlineSession = SessionSummary(
  sessionId: 'session-test',
  sessionRevision: '11111111-1111-4111-8111-111111111111',
  sessionName: '测试会话',
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
);

const observerSession = SessionSummary(
  sessionId: 'session-observer',
  sessionRevision: '22222222-2222-4222-8222-222222222222',
  sessionName: '观察会话',
  model: 'test/observer',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.observer,
);

const historySession = SessionSummary(
  sessionId: 'session-history',
  sessionRevision: '33333333-3333-4333-8333-333333333333',
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  accessMode: SessionAccessMode.observer,
  historyAvailable: true,
  historyOnly: true,
  canPrompt: false,
);

void main() {
  testWidgets('offline workspace shows the TSPi waiting state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: offlineWorkspace,
          session: offlineSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TSPi 尚未启动'), findsOneWidget);
    expect(find.text('./TSPi --workspace ts_001 --phone'), findsOneWidget);
    expect(find.text('当前会话没有消息'), findsNothing);
    expect(find.text('重新检测'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnect preserves messages and the unsent draft', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      snapshot: TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[userMessage('已有消息')],
        lastEventId: 'epoch:0',
      ),
    );
    const onlineWorkspace = WorkspaceSummary(
      id: 'ts_001',
      name: 'ts_001',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      liveSessionCount: 1,
      sessionCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: onlineWorkspace,
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '尚未发送的草稿');

    gateway.addWorkspaceState(RuntimeState.offline);
    await tester.pump();

    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller!.text, '尚未发送的草稿');
    expect(composer.enabled, isFalse);
    expect(find.text('已有消息'), findsOneWidget);
    expect(find.text('TSPi 已断开，重新启动后将自动恢复。'), findsOneWidget);
    expect(gateway.sentMessages, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline history shows its timeline in read-only mode', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[historySession],
      snapshot: TsPhoneMessageSnapshot(
        sessionId: 'session-history',
        sessionRevision: '33333333-3333-4333-8333-333333333333',
        messages: <Object?>[userMessage('已有历史消息')],
        lastEventId: 'history:0',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: offlineWorkspace,
          session: historySession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已有历史消息'), findsOneWidget);
    expect(find.textContaining('历史会话'), findsOneWidget);
    expect(find.textContaining('消息来自本机历史记录'), findsNothing);
    expect(find.text('只读观察模式'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.byTooltip('同步消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace list distinguishes an offline TSPi', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway(
      workspaces: const <WorkspaceSummary>[offlineWorkspace],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('离线'), findsOneWidget);
    expect(find.text('0 在线'), findsNothing);
    expect(find.text('研究目录'), findsNothing);
    expect(find.text('tsphone.example.test'), findsNothing);
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    expect(find.textContaining('无法连接 TS Phone'), findsNothing);
    expect(find.byType(TsGlassAppBar), findsOneWidget);
    expect(find.byType(TsStatusListTile), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TsStatusListTile),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workspace status cards preserve state at 320px with large text',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = UiFakeGateway(
        workspaces: const <WorkspaceSummary>[
          WorkspaceSummary(
            id: 'live-workspace',
            name: 'Long active research workspace',
            runtimeState: RuntimeState.running,
            isStreaming: true,
            liveSessionCount: 2,
            sessionCount: 4,
          ),
          offlineWorkspace,
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: TsPhoneTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: WorkspaceListPage(
            settings: _settings,
            onOpenSettings: () {},
            gatewayBuilder: (_) => gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
      expect(find.text('CONNECTED'), findsNothing);
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('2 LIVE'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('0 LIVE'), findsNothing);
      final tiles = tester.widgetList<TsStatusListTile>(
        find.byType(TsStatusListTile),
      );
      expect(tiles, hasLength(2));
      expect(tiles.every((tile) => tile.showStatusIndicator), isTrue);
      expect(
        find.descendant(
          of: find.byType(TsStatusListTile),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace cards fit dark mode at 320px and 2x text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(
          id: 'ts_long_workspace_id',
          name: 'Long transition-state research workspace',
          runtimeState: RuntimeState.idle,
          isStreaming: false,
          liveSessionCount: 1,
          sessionCount: 3,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('1 LIVE'), findsOneWidget);
    expect(find.text('Research workspaces'), findsNothing);
    expect(find.text('tsphone.example.test'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session list distinguishes controller and observer sessions', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[controllerSession, observerSession],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionListPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'ts_001',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 2,
            sessionCount: 2,
          ),
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试会话'), findsOneWidget);
    expect(find.text('观察会话'), findsOneWidget);
    expect(find.text('主会话'), findsOneWidget);
    expect(find.text('只读会话 · test/observer'), findsOneWidget);
    expect(find.text('就绪'), findsNWidgets(2));
    expect(find.byType(TsStatusListTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('session list keeps active work ahead of history', (
    WidgetTester tester,
  ) async {
    const generatingSession = SessionSummary(
      sessionId: 'session-running',
      sessionRevision: '44444444-4444-4444-8444-444444444444',
      sessionName: '生成中的会话',
      runtimeState: RuntimeState.running,
      isStreaming: true,
      accessMode: SessionAccessMode.controller,
    );
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[
        historySession,
        observerSession,
        controllerSession,
        generatingSession,
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionListPage(
          settings: _settings,
          workspace: offlineWorkspace,
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final generatingY = tester.getTopLeft(find.text('生成中的会话')).dy;
    final observerY = tester.getTopLeft(find.text('观察会话')).dy;
    final controllerY = tester.getTopLeft(find.text('测试会话')).dy;
    final historyY = tester
        .getTopLeft(find.text('历史会话', findRichText: true))
        .dy;
    expect(generatingY, lessThan(observerY));
    expect(observerY, lessThan(controllerY));
    expect(controllerY, lessThan(historyY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('English session hierarchy fits 320px with large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[
        SessionSummary(
          sessionId: 'session-controller-long',
          sessionRevision: '11111111-1111-4111-8111-111111111111',
          sessionName: 'A long transition-state controller session',
          model: 'provider/a-very-long-model-name',
          runtimeState: RuntimeState.running,
          isStreaming: true,
          accessMode: SessionAccessMode.controller,
        ),
        SessionSummary(
          sessionId: 'session-history-long',
          sessionRevision: '33333333-3333-4333-8333-333333333333',
          runtimeState: RuntimeState.offline,
          isStreaming: false,
          accessMode: SessionAccessMode.observer,
          historyAvailable: true,
          historyOnly: true,
          canPrompt: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SessionListPage(
          settings: _settings,
          workspace: offlineWorkspace,
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Generating'), findsOneWidget);
    expect(find.text('History session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace list refreshes after the app resumes', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway(
      workspaces: const <WorkspaceSummary>[offlineWorkspace],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ts_001'), findsOneWidget);

    gateway.workspaces = const <WorkspaceSummary>[];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('ts_001'), findsNothing);
    expect(find.text('没有可用研究目录'), findsOneWidget);
    expect(gateway.listWorkspacesCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('session list refreshes after the app resumes', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[controllerSession],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SessionListPage(
          settings: _settings,
          workspace: offlineWorkspace,
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试会话'), findsOneWidget);

    gateway.sessions = const <SessionSummary>[];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('测试会话'), findsNothing);
    expect(find.text('没有会话历史'), findsOneWidget);
    expect(gateway.listSessionsCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('narrow generation keeps controls inside a stable composer', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway();
    const workspace = WorkspaceSummary(
      id: 'ts_001',
      name: 'ts_001',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      liveSessionCount: 1,
      sessionCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: ChatPage(
          settings: _settings,
          workspace: workspace,
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('chat-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chat-back')), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-send')), findsOneWidget);
    final idleSendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(idleSendButton.onPressed, isNull);
    final idleComposerWidth = tester
        .getSize(find.byKey(const ValueKey<String>('chat-composer')))
        .width;
    final idleFieldWidth = tester.getSize(find.byType(TextField)).width;

    gateway.addWorkspaceState(RuntimeState.running);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Stop generation'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-stop')), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Ask or instruct session...',
    );
    final fieldBottom = tester.getBottomRight(find.byType(TextField)).dy;
    final stopBottom = tester
        .getBottomRight(find.byKey(const ValueKey<String>('composer-stop')))
        .dy;
    expect((fieldBottom - stopBottom).abs(), lessThan(1));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('chat-composer'))).width,
      idleComposerWidth,
    );
    expect(tester.getSize(find.byType(TextField)).width, idleFieldWidth);
    expect(find.textContaining('GENERATING · session'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '排队消息');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('composer-send')), findsOneWidget);
    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    expect(sendButton.onPressed, isNotNull);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    await tester.pumpAndSettle();
    expect(gateway.sentMessages, <String>['排队消息']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authentication failure points to connection settings', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway(
      listError: const TsPhoneApiException(
        'Unauthorized',
        statusCode: 401,
        code: 'unauthorized',
      ),
    );
    var openedSettings = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () => openedSettings = true,
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('认证失败，请检查访问令牌'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.tap(find.text('连接设置'));
    expect(openedSettings, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'streaming stays lightweight until the completed Markdown arrives',
    (WidgetTester tester) async {
      final gateway = UiFakeGateway(
        snapshot: TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: '11111111-1111-4111-8111-111111111111',
          messages: <Object?>[userMessage('已有 **Markdown** 消息')],
          lastEventId: 'epoch:0',
        ),
      );
      const onlineWorkspace = WorkspaceSummary(
        id: 'ts_001',
        name: 'ts_001',
        runtimeState: RuntimeState.idle,
        isStreaming: false,
        liveSessionCount: 1,
        sessionCount: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            settings: _settings,
            workspace: onlineWorkspace,
            session: controllerSession,
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownMessage), findsOneWidget);

      gateway.addStreamingStart();
      await tester.pump();
      gateway.addStreamingDelta('正在生成 **未完成** 的公式：\$x');
      await tester.pump(const Duration(milliseconds: 120));

      final streamingText = tester.widget<Text>(
        find.byKey(const ValueKey<String>('streaming-message-text')),
      );
      expect(streamingText.data, '正在生成 **未完成** 的公式：\$x');
      expect(find.byType(MarkdownMessage), findsOneWidget);

      gateway.addAssistantMessageEnd('生成完成：**结果**');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('streaming-message-text')),
        findsNothing,
      );
      expect(find.byType(MarkdownMessage), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('streaming does not take over after the user scrolls up', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      snapshot: TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: List<Object?>.generate(
          24,
          (index) => userMessage('历史消息 $index\n这是一段用于验证生成中滚动的较长内容。'),
        ),
        lastEventId: 'epoch:0',
      ),
    );
    const onlineWorkspace = WorkspaceSummary(
      id: 'ts_001',
      name: 'ts_001',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      liveSessionCount: 1,
      sessionCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: onlineWorkspace,
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey<String>('chat-message-list'));
    final list = tester.widget<ListView>(listFinder);
    final position = list.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.extentAfter, lessThan(1));

    await tester.drag(listFinder, const Offset(0, 80));
    await tester.pumpAndSettle();
    final readingOffset = position.pixels;
    final distanceFromTail = position.maxScrollExtent - readingOffset;
    expect(distanceFromTail, greaterThan(24));
    expect(distanceFromTail, lessThan(140));
    expect(find.byTooltip('回到最新消息'), findsOneWidget);

    gateway.addStreamingDelta('正在生成的新内容，它不应该把用户拉回到页面底部。');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(position.pixels, closeTo(readingOffset, 1));
    expect(position.extentAfter, closeTo(distanceFromTail, 1));
    expect(
      find.byKey(const ValueKey<String>('streaming-message-text')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('回到最新消息'));
    await tester.pumpAndSettle();
    expect(position.extentAfter, lessThan(1));
    expect(find.textContaining('正在生成的新内容'), findsOneWidget);
    expect(find.byTooltip('回到最新消息'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long sessions can jump between the start and latest message', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      snapshot: TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: List<Object?>.generate(
          24,
          (index) => userMessage('历史消息 $index\n用于验证会话首尾快速导航。'),
        ),
        lastEventId: 'epoch:0',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'ts_001',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey<String>('chat-message-list'));
    final position = tester.widget<ListView>(listFinder).controller!.position;
    expect(position.extentAfter, lessThan(1));
    expect(find.byTooltip('回到会话开始'), findsOneWidget);
    expect(find.byTooltip('回到最新消息'), findsNothing);

    await tester.tap(find.byTooltip('回到会话开始'));
    await tester.pumpAndSettle();

    expect(position.extentBefore, lessThan(1));
    expect(find.byTooltip('回到会话开始'), findsNothing);
    expect(find.byTooltip('回到最新消息'), findsOneWidget);

    await tester.tap(find.byTooltip('回到最新消息'));
    await tester.pumpAndSettle();

    expect(position.extentAfter, lessThan(1));
    expect(find.byTooltip('回到会话开始'), findsOneWidget);
    expect(find.byTooltip('回到最新消息'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reaching the top loads earlier history without losing position',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = UiFakeGateway(
        snapshot: TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: '11111111-1111-4111-8111-111111111111',
          messages: List<Object?>.generate(
            24,
            (index) => userMessage('当前消息 ${index + 24}\n用于验证历史分页。'),
          ),
          messageIds: List<String>.generate(
            24,
            (index) => (index + 24).toRadixString(16).padLeft(8, '0'),
          ),
          hasMore: true,
          nextBefore: '00000018',
          lastEventId: 'epoch:0',
        ),
        earlierSnapshot: TsPhoneMessageSnapshot(
          sessionId: 'session-test',
          sessionRevision: '11111111-1111-4111-8111-111111111111',
          messages: List<Object?>.generate(
            24,
            (index) => userMessage('更早消息 $index\n用于验证历史分页。'),
          ),
          messageIds: List<String>.generate(
            24,
            (index) => index.toRadixString(16).padLeft(8, '0'),
          ),
          lastEventId: 'epoch:0',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            settings: _settings,
            workspace: const WorkspaceSummary(
              id: 'ts_001',
              name: 'ts_001',
              runtimeState: RuntimeState.idle,
              isStreaming: false,
              liveSessionCount: 1,
              sessionCount: 1,
            ),
            session: controllerSession,
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listFinder = find.byKey(
        const ValueKey<String>('chat-message-list'),
      );
      final position = tester.widget<ListView>(listFinder).controller!.position;
      await tester.tap(find.byTooltip('回到会话开始'));
      await tester.pumpAndSettle();

      expect(gateway.lastBefore, '00000018');
      expect(gateway.lastLimit, 200);
      expect(position.extentBefore, greaterThan(0));

      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      expect(find.textContaining('更早消息 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'structured timeline exposes activity progress and branch history',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = UiFakeGateway(
        timelineResponder: ({before, branch}) async => _uiTimelineSnapshot(
          branch: branch,
          hasMore: before == null && branch == null,
        ),
      );
      const timelineSession = SessionSummary(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        sessionName: 'Timeline session',
        runtimeState: RuntimeState.idle,
        isStreaming: false,
        accessMode: SessionAccessMode.controller,
        historyAvailable: true,
        capabilities: <String>{timelineCapability},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            settings: _settings,
            workspace: const WorkspaceSummary(
              id: 'ts_001',
              name: 'ts_001',
              runtimeState: RuntimeState.idle,
              isStreaming: false,
              liveSessionCount: 1,
              sessionCount: 1,
            ),
            session: timelineSession,
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已载入 2 / 2501 项'), findsOneWidget);
      expect(find.textContaining('子代理 · Compute · Inspect'), findsOneWidget);
      expect(find.text('加载全部历史'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('timeline-branch-menu')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-branch-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('分支 0002').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        '历史分支只读',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('positions initial timeline before revealing history', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final response = Completer<TsPhoneTimelineSnapshot>();
    final gateway = UiFakeGateway(
      timelineResponder: ({before, branch}) => response.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'ts_001',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: const SessionSummary(
            sessionId: 'session-test',
            sessionRevision: '11111111-1111-4111-8111-111111111111',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            accessMode: SessionAccessMode.controller,
            historyAvailable: true,
            capabilities: <String>{timelineCapability},
          ),
          gateway: gateway,
        ),
      ),
    );
    response.complete(_positioningTimelineSnapshot());
    await tester.pump();

    final hiddenTimeline = tester.widget<Opacity>(
      find.byKey(const ValueKey<String>('initial-timeline-positioning')),
    );
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey<String>('chat-message-list')),
    );
    expect(hiddenTimeline.opacity, 0);
    expect(
      list.controller!.position.pixels,
      list.controller!.position.maxScrollExtent,
    );

    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey<String>('initial-timeline-positioning')),
          )
          .opacity,
      1,
    );
    expect(find.textContaining('会话配置 · 模型切换'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval panel keeps structured context and retries in place', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway()
      ..approvalErrors.add(
        const TsPhoneApiException(
          'Unavailable',
          statusCode: 503,
          code: 'service_unavailable',
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'Transition-state workspace',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.addApproval(preview: 'Tool: bash\n\ncommand: pwd');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Confirmation required'), findsOneWidget);
    expect(find.text('Transition-state workspace'), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);
    expect(find.textContaining('command: pwd'), findsOneWidget);

    await tester.tap(find.text('Approve once'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Confirmation required'), findsOneWidget);
    expect(
      find.text('The TS Phone service is temporarily unavailable'),
      findsOneWidget,
    );

    await tester.tap(find.text('Approve once'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmation required'), findsNothing);
    expect(gateway.approvalDecisions, <bool>[true, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back explicitly rejects an approval', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'ts_001',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.addApproval();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(gateway.approvalDecisions, <bool>[false]);
    expect(find.text('需要你的确认'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired approval closes without submitting a stale decision', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'ts_001',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.addApproval(
      expiresAt: DateTime.now().add(const Duration(seconds: 2)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('需要你的确认'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('该授权请求已过期'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(gateway.approvalDecisions, isEmpty);
    expect(find.text('需要你的确认'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session replacement invalidates the visible approval', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: 'ts_001',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.addApproval();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('需要你的确认'), findsOneWidget);

    gateway.replaceSessionRevision('22222222-2222-4222-8222-222222222222');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('该授权属于旧会话，已失效'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(gateway.approvalDecisions, isEmpty);
    expect(find.text('需要你的确认'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval panel fits narrow screens with large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = UiFakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          settings: _settings,
          workspace: const WorkspaceSummary(
            id: 'ts_001',
            name: '很长的过渡态研究工作区名称',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            liveSessionCount: 1,
            sessionCount: 1,
          ),
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.addApproval(
      preview: List<String>.filled(20, 'command: long value').join('\n'),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('仅批准本次'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    expect(tester.getBottomRight(find.text('拒绝')).dy, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });
}

const offlineWorkspace = WorkspaceSummary(
  id: 'ts_001',
  name: 'ts_001',
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  liveSessionCount: 0,
  sessionCount: 1,
);

class UiFakeGateway implements TsPhoneGateway {
  UiFakeGateway({
    this.workspaces = const <WorkspaceSummary>[],
    this.sessions = const <SessionSummary>[controllerSession],
    TsPhoneMessageSnapshot? snapshot,
    this.earlierSnapshot,
    this.listError,
    this.timelineResponder,
  }) : snapshot =
           snapshot ??
           const TsPhoneMessageSnapshot(
             sessionId: 'session-test',
             sessionRevision: '11111111-1111-4111-8111-111111111111',
             messages: <Object?>[],
             lastEventId: 'epoch:0',
           );

  List<WorkspaceSummary> workspaces;
  List<SessionSummary> sessions;
  TsPhoneMessageSnapshot snapshot;
  TsPhoneMessageSnapshot? earlierSnapshot;
  String? lastBefore;
  int? lastLimit;
  final Object? listError;
  final Future<TsPhoneTimelineSnapshot> Function({
    String? before,
    String? branch,
  })?
  timelineResponder;
  final List<String> sentMessages = <String>[];
  final List<bool> approvalDecisions = <bool>[];
  final List<Object> approvalErrors = <Object>[];
  final StreamController<TsPhoneEvent> _events =
      StreamController<TsPhoneEvent>.broadcast();
  int _sequence = 0;
  int listWorkspacesCalls = 0;
  int listSessionsCalls = 0;

  void addApproval({
    String id = 'approval-1',
    String preview = 'Tool: bash',
    DateTime? expiresAt,
  }) {
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        instanceEpoch: 'instance-1',
        sessionGeneration: 1,
        type: 'approval.request',
        payload: <String, Object?>{
          'id': id,
          'method': 'confirm',
          'toolName': 'bash',
          'preview': preview,
          'turnId': 'turn-1',
          'toolCallId': 'tool-1',
          'expiresAt':
              (expiresAt ?? DateTime.now().add(const Duration(minutes: 1)))
                  .toIso8601String(),
        },
        at: DateTime.now(),
      ),
    );
  }

  void replaceSessionRevision(String revision) {
    snapshot = TsPhoneMessageSnapshot(
      sessionId: snapshot.sessionId,
      sessionRevision: revision,
      messages: snapshot.messages,
      lastEventId: 'replacement:1',
    );
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: revision,
        instanceEpoch: 'instance-2',
        sessionGeneration: 2,
        type: 'session_state',
        payload: <String, Object?>{'state': 'idle', 'isStreaming': false},
        at: DateTime.now(),
      ),
    );
  }

  void addStreamingStart() {
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        instanceEpoch: 'instance-1',
        sessionGeneration: 1,
        type: 'message_start',
        payload: <String, Object?>{
          'message': <String, Object?>{'role': 'assistant'},
        },
        at: DateTime.utc(2026, 8, 16),
      ),
    );
  }

  void addWorkspaceState(RuntimeState state) {
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        instanceEpoch: state.isAvailable ? 'instance-1' : null,
        sessionGeneration: state.isAvailable ? 1 : null,
        type: 'session_state',
        payload: <String, Object?>{
          'state': switch (state) {
            RuntimeState.offline => 'offline',
            RuntimeState.connecting => 'connecting',
            RuntimeState.idle => 'idle',
            RuntimeState.running => 'running',
            RuntimeState.recoveryRequired => 'recovery_required',
          },
          'isStreaming': state == RuntimeState.running,
        },
        at: DateTime.utc(2026, 8, 15),
      ),
    );
  }

  void addStreamingDelta(String delta) {
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        instanceEpoch: 'instance-1',
        sessionGeneration: 1,
        type: 'message_update',
        payload: <String, Object?>{
          'assistantMessageEvent': <String, Object?>{
            'type': 'text_delta',
            'delta': delta,
          },
        },
        at: DateTime.utc(2026, 8, 16),
      ),
    );
  }

  void addAssistantMessageEnd(String text) {
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        instanceEpoch: 'instance-1',
        sessionGeneration: 1,
        type: 'message_end',
        payload: <String, Object?>{
          'message': <String, Object?>{
            'role': 'assistant',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': text},
            ],
            'timestamp': 1,
          },
        },
        at: DateTime.utc(2026, 8, 16),
      ),
    );
  }

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId,
    String sessionRevision,
  ) async {}

  @override
  void close() {
    unawaited(_events.close());
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) {
    onConnected?.call();
    return _events.stream;
  }

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) async {
    lastBefore = before;
    lastLimit = limit;
    final earlier = earlierSnapshot;
    if (before != null && earlier != null) return earlier;
    return snapshot;
  }

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) {
    final responder = timelineResponder;
    if (responder == null) {
      throw UnsupportedError('Timeline is not configured for this test');
    }
    return responder(before: before, branch: branch);
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    listWorkspacesCalls += 1;
    if (listError case final error?) throw error;
    return workspaces;
  }

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    listSessionsCalls += 1;
    return sessions;
  }

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async {
    approvalDecisions.add(approved);
    if (approvalErrors.isNotEmpty) throw approvalErrors.removeAt(0);
  }

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) async {
    sentMessages.add(message);
  }

  @override
  Future<Map<String, Object?>> version() async => <String, Object?>{};
}

Map<String, Object?> userMessage(String text) => <String, Object?>{
  'role': 'user',
  'content': <Object?>[
    <String, Object?>{'type': 'text', 'text': text},
  ],
  'timestamp': 1,
};

TsPhoneTimelineSnapshot _uiTimelineSnapshot({
  String? branch,
  required bool hasMore,
}) {
  final inactive = branch == '00000002';
  return TsPhoneTimelineSnapshot(
    sessionId: 'session-test',
    sessionRevision: '11111111-1111-4111-8111-111111111111',
    items: <SessionTimelineItem>[
      TimelineMessageItem(
        id: inactive ? '00000002' : '00000010',
        turnId: '00000001',
        message: ChatMessage.fromJson(
          userMessage(inactive ? '历史分支' : '当前研究请求'),
        ),
      ),
      if (!inactive)
        const TimelineActivityItem(
          id: '00000011',
          turnId: '00000001',
          activity: TimelineActivity(
            category: TimelineActivityCategory.subagent,
            status: TimelineActivityStatus.completed,
            title: 'subagent_run',
            role: 'compute',
            operation: 'inspect',
            nodeRefs: <String>['node_1'],
            durationMs: 1200,
            totalTokens: 42,
          ),
        ),
    ],
    history: TimelineHistorySummary(
      totalItems: inactive ? 1 : 2501,
      messageCount: inactive ? 1 : 1800,
      activityCount: inactive ? 0 : 701,
      turnCount: inactive ? 1 : 80,
      activeBranchId: '00000012',
      selectedBranchId: inactive ? '00000002' : '00000012',
      branches: const <TimelineBranchSummary>[
        TimelineBranchSummary(
          id: '00000002',
          active: false,
          itemCount: 1,
          messageCount: 1,
          activityCount: 0,
          turnCount: 1,
        ),
        TimelineBranchSummary(
          id: '00000012',
          active: true,
          itemCount: 2501,
          messageCount: 1800,
          activityCount: 701,
          turnCount: 80,
        ),
      ],
    ),
    hasMore: hasMore,
    nextBefore: hasMore ? '00000010' : null,
    lastEventId: 'epoch:0',
    capabilities: <String>{
      timelineCapability,
      timelinePaginationCapability,
      timelineBranchesCapability,
      if (!inactive) promptCapability,
      if (!inactive) abortCapability,
    },
  );
}

TsPhoneTimelineSnapshot _positioningTimelineSnapshot() {
  final items = List<SessionTimelineItem>.generate(
    40,
    (index) => TimelineActivityItem(
      id: (index + 1).toRadixString(16).padLeft(8, '0'),
      activity: const TimelineActivity(
        category: TimelineActivityCategory.configuration,
        status: TimelineActivityStatus.recorded,
        title: 'model_change',
        detail: 'gpt-5.6-sol',
      ),
    ),
  );
  return TsPhoneTimelineSnapshot(
    sessionId: 'session-test',
    sessionRevision: '11111111-1111-4111-8111-111111111111',
    items: items,
    history: const TimelineHistorySummary(
      totalItems: 40,
      messageCount: 0,
      activityCount: 40,
      turnCount: 0,
      activeBranchId: '00000040',
      selectedBranchId: '00000040',
      branches: <TimelineBranchSummary>[
        TimelineBranchSummary(
          id: '00000040',
          active: true,
          itemCount: 40,
          messageCount: 0,
          activityCount: 40,
          turnCount: 0,
        ),
      ],
    ),
    hasMore: false,
    lastEventId: 'epoch:0',
    capabilities: const <String>{timelineCapability},
  );
}
