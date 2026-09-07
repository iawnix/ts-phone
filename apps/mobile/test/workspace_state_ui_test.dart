import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/chat/timeline_widgets.dart';
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

const longSessionId =
    'session-history-0123456789abcdef0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const longHistorySession = SessionSummary(
  sessionId: longSessionId,
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
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat header keeps runtime metadata in session details', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = UiFakeGateway();
    final session = SessionSummary(
      sessionId: 'session-test',
      sessionRevision: '11111111-1111-4111-8111-111111111111',
      sessionName: '测试会话',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      accessMode: SessionAccessMode.controller,
      runtime: SessionRuntimeSnapshot(
        model: const SessionRuntimeModel(provider: 'cpa', id: 'gpt-5.6-sol'),
        context: const SessionContextUsage(
          usedTokens: 78214,
          limitTokens: 128000,
        ),
        updatedAt: DateTime.utc(2026, 8, 31, 6, 32, 18),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
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
          session: session,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final compactStatus = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('chat-compact-status')),
    );
    expect(compactStatus.properties.label, '已连接 · 可发送');
    expect(find.text('已连接 · 可发送'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.text('测试会话'), findsOneWidget);
    final appBarRect = tester.getRect(find.byType(AppBar));
    expect(
      appBarRect.contains(tester.getRect(find.text('测试会话')).center),
      isTrue,
    );
    expect(
      appBarRect.contains(
        tester
            .getRect(find.byKey(const ValueKey<String>('chat-compact-status')))
            .center,
      ),
      isTrue,
    );
    expect(find.textContaining('gpt-5.6-sol'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('chat-session-details')),
    );
    await tester.pumpAndSettle();

    expect(find.text('会话详情'), findsOneWidget);
    expect(find.text('gpt-5.6-sol'), findsOneWidget);
    expect(find.text('78,214 / 128,000'), findsOneWidget);
    expect(find.text('49,786 · 39%'), findsOneWidget);
    expect(find.text('Pi 估算'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('session-identity-group')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('session-runtime-group')),
      findsOneWidget,
    );
    expect(find.textContaining('https://'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unnamed chats keep opaque identity in details only', (
    WidgetTester tester,
  ) async {
    Future<void> pumpSession(String sessionId, String sessionRevision) async {
      final session = SessionSummary(
        sessionId: sessionId,
        sessionRevision: sessionRevision,
        runtimeState: RuntimeState.offline,
        isStreaming: false,
        accessMode: SessionAccessMode.observer,
        historyAvailable: true,
        historyOnly: true,
        canPrompt: false,
      );
      final gateway = UiFakeGateway(
        sessions: <SessionSummary>[session],
        snapshot: TsPhoneMessageSnapshot(
          sessionId: sessionId,
          sessionRevision: sessionRevision,
          messages: const <Object?>[],
          lastEventId: 'history:0',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ChatPage(
            key: ValueKey<String>(sessionId),
            settings: _settings,
            workspace: offlineWorkspace,
            session: session,
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Untitled conversation'), findsOneWidget);
      expect(find.textContaining(sessionId.substring(0, 8)), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-session-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-technical-details')));
      await tester.pumpAndSettle();
      expect(find.text(sessionId), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    await pumpSession(
      '11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '11111111-1111-4111-8111-111111111111',
    );

    await pumpSession(
      '22222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      '22222222-2222-4222-8222-222222222222',
    );
    expect(find.text('Session 11111111'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long models and unknown post-compaction usage fit narrow UI', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = UiFakeGateway();
    final session = SessionSummary(
      sessionId: 'session-test',
      sessionRevision: '11111111-1111-4111-8111-111111111111',
      sessionName: 'Long model session',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      accessMode: SessionAccessMode.controller,
      runtime: SessionRuntimeSnapshot(
        model: const SessionRuntimeModel(
          provider: 'openai-compatible-provider',
          id: 'a-very-long-frontier-reasoning-model-name-for-layout-testing',
        ),
        context: const SessionContextUsage(
          usedTokens: null,
          limitTokens: 128000,
        ),
        updatedAt: DateTime.utc(2026, 8, 31, 6, 33, 18),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.dark(),
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
          session: session,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected · Ready'), findsOneWidget);
    expect(find.textContaining('a-very-long-frontier'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('chat-session-details')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsOneWidget);
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
    expect(composer.enabled, isTrue);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed,
      isNull,
    );
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
    expect(find.text('未命名会话'), findsOneWidget);
    expect(find.text('历史 · 只读'), findsOneWidget);
    expect(find.textContaining('消息来自本机历史记录'), findsNothing);
    expect(find.text('只读观察模式'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('chat-read-only-bar')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('chat-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chat-session-details')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history state remains in navigation at 320px and 2x text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[longHistorySession],
      snapshot: const TsPhoneMessageSnapshot(
        sessionId: longSessionId,
        sessionRevision: '33333333-3333-4333-8333-333333333333',
        messages: <Object?>[],
        lastEventId: 'history:0',
      ),
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
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ChatPage(
          settings: _settings,
          workspace: offlineWorkspace,
          session: longHistorySession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final historyStatus = find.byKey(
      const ValueKey<String>('chat-history-status'),
    );
    expect(historyStatus, findsOneWidget);
    expect(
      tester.widget<Semantics>(historyStatus).properties.label,
      'History · Read-only',
    );
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('chat-read-only-bar')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('session details collapse when no runtime snapshot exists', (
    WidgetTester tester,
  ) async {
    String? copiedSessionId;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedSessionId =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': copiedSessionId};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[longHistorySession],
      snapshot: const TsPhoneMessageSnapshot(
        sessionId: longSessionId,
        sessionRevision: '33333333-3333-4333-8333-333333333333',
        messages: <Object?>[],
        lastEventId: 'history:0',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
        home: ChatPage(
          settings: _settings,
          workspace: offlineWorkspace,
          session: longHistorySession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('chat-session-details')),
    );
    await tester.pumpAndSettle();

    expect(find.text('此会话未保存运行时快照。'), findsOneWidget);
    expect(find.text(longSessionId), findsNothing);
    await tester.tap(find.byKey(const ValueKey('session-technical-details')));
    await tester.pumpAndSettle();
    expect(find.text(longSessionId), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('session-runtime-unavailable')),
      findsOneWidget,
    );
    expect(find.text('模型'), findsNothing);
    expect(find.text('Provider'), findsNothing);
    expect(find.text('上下文'), findsNothing);
    expect(find.text('剩余'), findsNothing);
    expect(find.text('测量方式'), findsNothing);
    expect(find.text('更新时间'), findsNothing);
    expect(find.text('暂无数据'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('copy-session-id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byTooltip('会话 ID 已复制'), findsOneWidget);
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      longSessionId,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('live observer sessions remain promptable', (
    WidgetTester tester,
  ) async {
    final gateway = UiFakeGateway(
      sessions: const <SessionSummary>[observerSession],
      snapshot: const TsPhoneMessageSnapshot(
        sessionId: 'session-observer',
        sessionRevision: '22222222-2222-4222-8222-222222222222',
        messages: <Object?>[],
        lastEventId: 'observer:0',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
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
          session: observerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已连接 · 可发送'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chat-composer')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      find.byKey(const ValueKey<String>('chat-read-only-bar')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workspace list keeps offline projects accessible without alarm labels',
    (WidgetTester tester) async {
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

      expect(find.textContaining('TSPi 未启动', findRichText: true), findsNothing);
      expect(find.text('0 在线'), findsNothing);
      expect(find.text('研究目录'), findsNothing);
      expect(find.text('tsphone.example.test'), findsNothing);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.textContaining('无法连接 TS Phone'), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      final row = find.byKey(const ValueKey<String>('workspace-row-ts_001'));
      expect(row, findsOneWidget);
      final rowRect = tester.getRect(row);
      expect(rowRect.left, TsPhoneSpacing.large);
      expect(
        rowRect.right,
        tester.view.physicalSize.width / tester.view.devicePixelRatio -
            TsPhoneSpacing.large,
      );
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: row, matching: find.byType(InkWell)),
            )
            .onTap,
        isNotNull,
      );
      expect(
        find.descendant(of: row, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workspace list uses consistent inset rows at 320px with large text',
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

      expect(find.byIcon(Icons.folder_outlined), findsNWidgets(2));
      expect(find.text('CONNECTED'), findsNothing);
      expect(
        find.textContaining('RUNNING', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('2 LIVE'), findsNothing);
      final offlineStatus = find.text('1 session');
      expect(offlineStatus, findsOneWidget);
      expect(find.text('0 LIVE'), findsNothing);
      final liveRow = find.byKey(
        const ValueKey<String>('workspace-row-live-workspace'),
      );
      final offlineRow = find.byKey(
        const ValueKey<String>('workspace-row-ts_001'),
      );
      expect(liveRow, findsOneWidget);
      expect(offlineRow, findsOneWidget);
      final liveRect = tester.getRect(liveRow);
      final offlineRect = tester.getRect(offlineRow);
      expect(liveRect.left, TsPhoneSpacing.large);
      expect(offlineRect.left, TsPhoneSpacing.large);
      expect(liveRect.width, offlineRect.width);
      expect(offlineRect.top - liveRect.bottom, TsPhoneSpacing.small);
      expect(
        find.descendant(of: liveRow, matching: find.byType(TsInlineStatus)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: offlineRow, matching: find.byType(TsInlineStatus)),
        findsNothing,
      );
      expect(find.byType(TsStatusBadge), findsNothing);
      expect(
        tester.renderObject<RenderParagraph>(offlineStatus).didExceedMaxLines,
        isFalse,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('workspace-list')),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace rows fit dark mode at 320px and 2x text', (
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
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('1 LIVE'), findsNothing);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.textContaining('Last sync'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-connection')));
    await tester.pumpAndSettle();
    final serviceMetadata = find.textContaining('TS Phone service');
    final syncMetadata = find.textContaining('Last sync');
    expect(serviceMetadata, findsWidgets);
    expect(syncMetadata, findsOneWidget);
    expect(
      tester
          .renderObject<RenderParagraph>(serviceMetadata.first)
          .didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.renderObject<RenderParagraph>(syncMetadata).didExceedMaxLines,
      isFalse,
    );
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
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
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

    expect(
      find.textContaining('Generating', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('History session', findRichText: true),
      findsOneWidget,
    );
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
    expect(find.text('还没有项目'), findsOneWidget);
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
    expect(find.text('还没有会话'), findsOneWidget);
    expect(gateway.listSessionsCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('narrow generation keeps controls inside a stable composer', (
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
        messages: <Object?>[userMessage('Keep the latest result visible')],
        lastEventId: 'epoch:0',
      ),
    );
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
        theme: TsPhoneTheme.light(),
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
    expect(find.byKey(const ValueKey<String>('chat-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chat-session-details')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const ValueKey<String>('composer-action-slot')),
      findsOneWidget,
    );
    final idleComposerWidth = tester
        .getSize(find.byKey(const ValueKey<String>('chat-composer')))
        .width;
    final idleFieldWidth = tester.getSize(find.byType(TextField)).width;
    final messageListRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-message-list')),
    );
    final appBarRect = tester.getRect(find.byType(AppBar));
    final idleComposerRect = tester.getRect(
      find.byKey(const ValueKey<String>('chat-composer')),
    );
    final messageList = tester.widget<ListView>(
      find.byKey(const ValueKey<String>('chat-message-list')),
    );
    final messagePadding = messageList.padding! as EdgeInsets;
    expect(messageListRect.top, greaterThanOrEqualTo(appBarRect.bottom));
    expect(messageListRect.bottom, greaterThan(idleComposerRect.top));
    expect(messagePadding.bottom, greaterThan(idleComposerRect.height));

    gateway.addWorkspaceState(RuntimeState.running);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Stop generation'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('live-run-stop')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-stop')), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Message',
    );
    final liveStopBottom = tester
        .getBottomRight(find.byKey(const ValueKey<String>('live-run-stop')))
        .dy;
    final composerTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('chat-composer')))
        .dy;
    expect(liveStopBottom, lessThanOrEqualTo(composerTop));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('chat-composer'))).width,
      idleComposerWidth,
    );
    expect(tester.getSize(find.byType(TextField)).width, idleFieldWidth);
    expect(find.text('Generating'), findsOneWidget);

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

  testWidgets('a pending send can finish after the chat page is disposed', (
    WidgetTester tester,
  ) async {
    final sendResponse = Completer<void>();
    final gateway = UiFakeGateway()..nextSend = sendResponse.future;

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
    await tester.enterText(find.byType(TextField), 'finish after leaving');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('composer-send')));
    await tester.pump();

    expect(gateway.sentMessages, isEmpty);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    sendResponse.complete();
    await tester.pumpAndSettle();

    expect(gateway.sentMessages, <String>['finish after leaving']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop generation requires explicit confirmation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
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
    gateway.addWorkspaceState(RuntimeState.running);
    await tester.pumpAndSettle();

    final requestStop = tester
        .widget<IconButton>(find.byKey(const ValueKey<String>('live-run-stop')))
        .onPressed!;
    requestStop();
    requestStop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        'Stop the current generation? The partial response may be incomplete.',
      ),
      findsOneWidget,
    );
    expect(gateway.abortCalls, 0);

    await tester.tap(find.widgetWithText(TextButton, 'Keep generating'));
    await tester.pumpAndSettle();
    expect(gateway.abortCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('live-run-stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stop generation'));
    await tester.pumpAndSettle();

    expect(gateway.abortCalls, 1);
    expect(gateway.lastAbortAgentRunId, 'run-ui-1');
    expect(find.text('Abort request sent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop confirmation cannot abort a later agent run', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
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
    gateway.addAgentLifecycleEvent('agent_start');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('live-run-stop')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    gateway.addAgentLifecycleEvent('agent_settled');
    await tester.pumpAndSettle();
    gateway.addAgentLifecycleEvent('agent_start');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Stop generation'));
    await tester.pumpAndSettle();

    expect(gateway.abortCalls, 0);
    expect(find.text('Abort request sent'), findsNothing);
    expect(
      find.text('The active generation changed. Nothing was stopped.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('soft keyboard keeps the multiline composer visible', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final gateway = UiFakeGateway(
      snapshot: TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[
          userMessage('Keep the composer above the keyboard'),
        ],
        lastEventId: 'epoch:0',
      ),
    );
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
        theme: TsPhoneTheme.light(),
        home: ChatPage(
          settings: _settings,
          workspace: workspace,
          session: controllerSession,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    await tester.tap(textField);
    await tester.pump();
    final closedComposerBottom = tester
        .getRect(find.byKey(const ValueKey<String>('chat-composer')))
        .bottom;

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    const keyboardTop = 700.0 - 280.0;
    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('chat-composer')))
          .bottom,
      lessThanOrEqualTo(keyboardTop),
    );

    await tester.enterText(textField, '第一行\n第二行\n第三行');
    await tester.pumpAndSettle();

    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('chat-composer')))
          .bottom,
      lessThanOrEqualTo(keyboardTop),
    );
    expect(tester.getRect(textField).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.widget<TextField>(textField).focusNode!.hasFocus, isTrue);
    expect(
      tester.widget<TextField>(textField).controller!.text,
      contains('\n'),
    );

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('chat-composer')))
          .bottom,
      closedComposerBottom,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard keeps a large live composer above its controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = UiFakeGateway(
      snapshot: TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        messages: <Object?>[userMessage('Keep every live control visible')],
        lastEventId: 'epoch:0',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
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
    gateway.addWorkspaceState(RuntimeState.running);
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    await tester.tap(textField);
    await tester.enterText(
      textField,
      'one\ntwo\nthree\nfour\nfive\nsix\nseven',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    const keyboardTop = 700.0 - 280.0;
    final composer = tester.getRect(
      find.byKey(const ValueKey<String>('chat-composer')),
    );
    final appBar = tester.getRect(find.byType(AppBar));
    final stop = tester.getRect(
      find.byKey(const ValueKey<String>('live-run-stop')),
    );
    expect(composer.top, greaterThanOrEqualTo(appBar.bottom));
    expect(composer.bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(textField).bottom, lessThanOrEqualTo(keyboardTop));
    expect(stop.top, greaterThanOrEqualTo(appBar.bottom));
    expect(stop.bottom, lessThanOrEqualTo(composer.top));
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
    expect(find.byTooltip('回到会话开始'), findsNothing);
    expect(find.byTooltip('回到最新消息'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到会话开始'));
    await tester.pumpAndSettle();

    expect(position.extentBefore, lessThan(1));
    expect(find.byTooltip('回到会话开始'), findsNothing);
    expect(find.byTooltip('回到最新消息'), findsOneWidget);

    await tester.tap(find.byTooltip('回到最新消息'));
    await tester.pumpAndSettle();

    expect(position.extentAfter, lessThan(1));
    expect(find.byTooltip('回到会话开始'), findsNothing);
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
      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回到会话开始'));
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
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: TsPhoneTheme.light(),
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
      expect(find.text('Compute · Inspect'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('1.2 秒'), findsOneWidget);
      expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsNothing);
      expect(find.textContaining('Node 1'), findsNothing);
      expect(find.textContaining('42 tokens'), findsNothing);
      expect(find.text('加载全部历史'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('timeline-view-filter')),
        findsOneWidget,
      );
      expect(find.text('Turn 80 · 1 条活动'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('timeline-history-menu')),
        findsOneWidget,
      );

      await tester.tap(find.text('活动'));
      await tester.pumpAndSettle();
      expect(find.text('当前研究请求'), findsNothing);
      expect(find.text('Compute · Inspect'), findsOneWidget);
      expect(find.text('Turn 80 · 1 条活动'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-view-filter')),
          matching: find.text('消息'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前研究请求'), findsOneWidget);
      expect(find.text('Compute · Inspect'), findsNothing);
      expect(find.text('Turn 80'), findsNothing);

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-activity-details-00000011'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Node 1'), findsOneWidget);
      expect(find.textContaining('42 tokens'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-history-menu')),
      );
      await tester.pumpAndSettle();
      expect(find.text('加载全部历史'), findsOneWidget);
      await tester.tap(find.text('分支 0002').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('chat-read-only-bar')),
        findsNothing,
      );
      expect(find.text('历史 · 只读'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('timeline filters preserve original turn numbering', () {
    final groups = groupTimelineItems(<SessionTimelineItem>[
      TimelineMessageItem(
        id: '00000010',
        turnId: 'turn-a',
        message: ChatMessage.fromJson(userMessage('message-only')),
      ),
      const TimelineActivityItem(
        id: '00000011',
        turnId: 'turn-b',
        activity: TimelineActivity(
          category: TimelineActivityCategory.research,
          status: TimelineActivityStatus.completed,
          title: 'activity-only',
        ),
      ),
      TimelineMessageItem(
        id: '00000012',
        turnId: 'turn-c',
        message: ChatMessage.fromJson(userMessage('mixed-turn')),
      ),
      const TimelineActivityItem(
        id: '00000013',
        turnId: 'turn-c',
        activity: TimelineActivity(
          category: TimelineActivityCategory.review,
          status: TimelineActivityStatus.recorded,
          title: 'mixed-turn-review',
        ),
      ),
    ], totalTurnCount: 8);

    expect(groups.map((group) => group.number), <int>[6, 7, 8]);
    expect(
      filterTimelineGroups(
        groups,
        TimelineViewFilter.messages,
      ).map((group) => group.number),
      <int>[6, 8],
    );
    expect(
      filterTimelineGroups(
        groups,
        TimelineViewFilter.activities,
      ).map((group) => group.number),
      <int>[7, 8],
    );
  });

  testWidgets('empty timeline filter remains recoverable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = UiFakeGateway(
      timelineResponder: ({before, branch}) async => TsPhoneTimelineSnapshot(
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        items: <SessionTimelineItem>[
          TimelineMessageItem(
            id: '00000001',
            turnId: 'turn-a',
            message: ChatMessage.fromJson(userMessage('Only message')),
          ),
        ],
        history: const TimelineHistorySummary(
          totalItems: 1,
          messageCount: 1,
          activityCount: 0,
          turnCount: 1,
          activeBranchId: '00000001',
          selectedBranchId: '00000001',
          branches: <TimelineBranchSummary>[
            TimelineBranchSummary(
              id: '00000001',
              active: true,
              itemCount: 1,
              messageCount: 1,
              activityCount: 0,
              turnCount: 1,
            ),
          ],
        ),
        hasMore: false,
        lastEventId: 'epoch:0',
        capabilities: const <String>{timelineCapability},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('timeline-view-filter')),
      findsOneWidget,
    );
    expect(find.text('Only message'), findsOneWidget);
    expect(find.text('Turn 1'), findsNothing);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Only message'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('timeline-filter-empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-view-filter')),
      findsOneWidget,
    );

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Only message'), findsOneWidget);
    expect(find.text('Turn 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('模型切换'), findsWidgets);
    expect(find.text('已记录'), findsWidgets);
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
    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.enableDrag, isFalse);
    expect(bottomSheet.showDragHandle, isFalse);
    final readableSurface = tester.widget<Material>(
      find.byKey(const ValueKey<String>('approval-readable-surface')),
    );
    final readableSurfaceContext = tester.element(
      find.byKey(const ValueKey<String>('approval-readable-surface')),
    );
    expect(
      readableSurface.color,
      Theme.of(readableSurfaceContext).colorScheme.surfaceContainerLowest,
    );
    final approveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('approval-approve')),
    );
    expect(
      approveButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      Theme.of(readableSurfaceContext).colorScheme.onTertiary,
    );

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

  testWidgets('approval countdown only announces urgency thresholds', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final gateway = UiFakeGateway();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(supportsAnnounce: true),
          child: child!,
        ),
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
    gateway.addApproval(
      expiresAt: DateTime.now().add(const Duration(seconds: 32)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    tester.takeAnnouncements();

    final countdown = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('approval-countdown')),
    );
    expect(countdown.properties.liveRegion, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeAnnouncements(), isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.takeAnnouncements(),
      contains(isAccessibilityAnnouncement('Expires in 30s')),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeAnnouncements(), isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('approval-reject')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
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
    expect(
      tester.getRect(find.text('该授权请求已过期')).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey<String>('chat-composer'))).top,
      ),
    );
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
  Future<void>? nextSend;
  final List<bool> approvalDecisions = <bool>[];
  final List<Object> approvalErrors = <Object>[];
  final StreamController<TsPhoneEvent> _events =
      StreamController<TsPhoneEvent>.broadcast();
  int _sequence = 0;
  int listWorkspacesCalls = 0;
  int listSessionsCalls = 0;
  int abortCalls = 0;
  int _agentRunSequence = 0;
  String? _activeAgentRunId;
  String? lastAbortAgentRunId;

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

  void addAgentLifecycleEvent(String type) {
    assert(type == 'agent_start' || type == 'agent_settled');
    if (type == 'agent_start') {
      _agentRunSequence += 1;
      _activeAgentRunId = 'run-ui-$_agentRunSequence';
    }
    final agentRunId = _activeAgentRunId;
    assert(agentRunId != null);
    _sequence += 1;
    _events.add(
      TsPhoneEvent(
        id: 'epoch:$_sequence',
        workspaceId: 'ts_001',
        sessionId: 'session-test',
        sessionRevision: '11111111-1111-4111-8111-111111111111',
        instanceEpoch: 'instance-1',
        sessionGeneration: 1,
        type: type,
        payload: <String, Object?>{'type': type, 'agentRunId': agentRunId},
        at: DateTime.utc(2026, 8, 16),
      ),
    );
    if (type == 'agent_settled') _activeAgentRunId = null;
  }

  void addWorkspaceState(RuntimeState state) {
    if (state == RuntimeState.running && _activeAgentRunId == null) {
      _agentRunSequence += 1;
      _activeAgentRunId = 'run-ui-$_agentRunSequence';
    } else if (state != RuntimeState.running) {
      _activeAgentRunId = null;
    }
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
          if (_activeAgentRunId != null) 'activeAgentRunId': _activeAgentRunId,
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
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) async {
    abortCalls += 1;
    lastAbortAgentRunId = agentRunId;
  }

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
    final pending = nextSend;
    nextSend = null;
    if (pending != null) await pending;
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
