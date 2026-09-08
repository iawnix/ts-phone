import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/settings_store.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/sessions/conversation_shell.dart';
import 'package:ts_phone/features/settings/settings_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/app_locale_preference.dart';
import 'package:ts_phone/models/app_theme_preference.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

final settings = ConnectionSettings(
  serverUrl: 'https://phone.test',
  token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);
const workspace = WorkspaceSummary(
  id: 'ts_001',
  name: 'Reaction pathways',
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  liveSessionCount: 0,
  sessionCount: 2,
);
const otherWorkspace = WorkspaceSummary(
  id: 'ts_002',
  name: 'Catalyst comparison',
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  liveSessionCount: 0,
  sessionCount: 2,
);

SessionSummary session(
  String id, {
  String managementRevision = 'unmanaged',
  Set<String> capabilities = const {'session.activate_mode'},
  SessionActivation? activation = const SessionActivation(
    modes: {SessionAccessMode.controller, SessionAccessMode.observer},
  ),
}) => SessionSummary(
  sessionId: id,
  sessionName: id == 'session_1'
      ? 'Transition-state search'
      : 'Alternative mechanism',
  sessionRevision: 'revision-1',
  runtimeState: RuntimeState.offline,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  historyAvailable: true,
  historyOnly: true,
  canPrompt: false,
  canActivate: true,
  managementRevision: managementRevision,
  activation: activation,
  capabilities: capabilities,
);

Widget shellApp(
  ConversationGateway gateway, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1,
  ConversationSelectionStore? store,
}) => RepaintBoundary(
  key: const ValueKey('capture-root'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? TsPhoneTheme.dark() : TsPhoneTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => ConversationShell(
        settings: settings,
        onOpenSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => SettingsPage(
              connectionSettings: settings,
              themePreference: dark
                  ? AppThemePreference.dark
                  : AppThemePreference.light,
              localePreference: locale.languageCode == 'zh'
                  ? AppLocalePreference.zh
                  : AppLocalePreference.en,
              onThemeChanged: (_) async {},
              onLocaleChanged: (_) async {},
              onEditConnection: () {},
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        selectionStore: store,
        gatewayBuilder: (_) => gateway,
      ),
    ),
  ),
);

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets(
    'cold start lists recent history without opening or activating it',
    (tester) async {
      final gateway = ConversationGateway();
      final store = MemorySelectionStore();
      await tester.pumpWidget(shellApp(gateway, store: store));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsNothing);
      expect(find.byKey(const ValueKey('chat-input')), findsNothing);
      expect(gateway.messageLimits, isEmpty);
      expect(gateway.activations, 0);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('recent-session-ts_001-session_2')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('recent-session-ts_001-session_1')),
              )
              .dy,
        ),
      );
      await openRecent(tester, sessionId: 'session_2');
      expect(find.byType(ChatPage), findsOneWidget);
      expect(
        tester.widget<ChatPage>(find.byType(ChatPage)).session.sessionId,
        'session_2',
      );
      expect(gateway.activations, 0);
      expect(gateway.messageLimits, [50]);
      expect(store.selected, ('ts_001', 'session_2'));
    },
  );

  testWidgets('sidebar switches histories immediately and restores drafts', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Preserve this draft',
    );
    await openSidebar(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Active'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sidebar-session-session_2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      isEmpty,
    );
    await openSidebar(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-session-session_1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      'Preserve this draft',
    );
    expect(gateway.activations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home limits recent rows and can retry a partial summary failure',
    (tester) async {
      final gateway = ConversationGateway()
        ..workspaces = [workspace, otherWorkspace]
        ..sessions = List.generate(
          8,
          (index) => session('session_${index + 1}'),
        )
        ..failedSummaryWorkspaces.add('ts_002');
      await tester.pumpWidget(shellApp(gateway));
      await tester.pumpAndSettle();
      final recentRows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'recent-session-',
            ),
      );
      expect(recentRows, findsNWidgets(5));
      expect(find.byTooltip('Retry'), findsOneWidget);
      expect(gateway.messageLimits, isEmpty);
      expect(gateway.activations, 0);
      gateway.failedSummaryWorkspaces.clear();
      await tester.tap(find.byTooltip('Retry'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retry'), findsNothing);
      expect(recentRows, findsNWidgets(5));
      expect(find.byType(ChatPage), findsNothing);
    },
  );

  testWidgets('new conversation skips the form and never starts the worker', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await openSidebar(tester);
    await tester.tap(find.byKey(const ValueKey('sidebar-new-session')));
    await tester.pumpAndSettle();
    expect(gateway.creations, 1);
    expect(gateway.activations, 0);
    expect(
      tester.widget<ChatPage>(find.byType(ChatPage)).session.sessionId,
      'session_3',
    );
  });

  testWidgets('activation is explicit and failure retains the input', (
    tester,
  ) async {
    final gateway = ConversationGateway()
      ..activation = Completer<SessionSummary>();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Compare both pathways',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('continue-session')));
    await tester.pump();
    expect(gateway.activations, 1);
    expect(find.byType(ChatPage), findsOneWidget);
    gateway.activation!.completeError(
      const TsPhoneApiException(
        'private diagnostic',
        statusCode: 503,
        code: 'session_writer_inspection_failed',
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(ChatPage)));
    expect(find.text(l10n.activationInspectionFailed), findsOneWidget);
    expect(find.text(l10n.activationFailed), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      'Compare both pathways',
    );
    expect(gateway.sent, 0);
  });

  testWidgets('pending creation keeps controls stable and honors back', (
    tester,
  ) async {
    final gateway = ConversationGateway()
      ..creation = Completer<SessionSummary>();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-row-ts_001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transition-state search'));
    await tester.pumpAndSettle();
    await openSidebar(tester);
    final create = find.byKey(const ValueKey('sidebar-new-session'));
    final bounds = tester.getRect(create);
    await tester.tap(create);
    await tester.pump(const Duration(milliseconds: 400));
    await openSidebar(tester);
    expect(tester.getRect(create), bounds);
    expect(tester.widget<ListTile>(create).onTap, isNull);
    expect(
      find.descendant(
        of: create,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(create);
    expect(gateway.creations, 1);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatPage), findsNothing);
    final listCreate = find.byKey(const ValueKey('create-session'));
    expect(tester.widget<IconButton>(listCreate).onPressed, isNull);
    await tester.tap(listCreate);
    await tester.pump();
    expect(gateway.creations, 1);
    expect(find.byType(Dialog), findsNothing);

    gateway.creation!.complete(session('session_3'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    expect(tester.widget<IconButton>(listCreate).onPressed, isNotNull);
    expect(
      gateway.sessions.map((value) => value.sessionId),
      contains('session_3'),
    );
    expect(gateway.activations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late creation does not replace a newer selection', (
    tester,
  ) async {
    final gateway = ConversationGateway()
      ..creation = Completer<SessionSummary>();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await openSidebar(tester);
    await tester.tap(find.byKey(const ValueKey('sidebar-new-session')));
    await tester.pump();
    await openSidebar(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sidebarCreate = find.byKey(const ValueKey('sidebar-new-session'));
    expect(sidebarCreate, findsOneWidget);
    expect(tester.widget<ListTile>(sidebarCreate).onTap, isNull);
    await tester.tap(find.byKey(const ValueKey('sidebar-home')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('recent-session-ts_001-session_2')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ChatPage>(find.byType(ChatPage)).session.sessionId,
      'session_2',
    );
    gateway.creation!.complete(session('session_3'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChatPage>(find.byType(ChatPage)).session.sessionId,
      'session_2',
    );
    expect(gateway.creations, 1);
    expect(gateway.activations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same session ID in another project has an independent draft', (
    tester,
  ) async {
    final gateway = ConversationGateway()
      ..workspaces = [workspace, otherWorkspace];
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'First project draft',
    );
    Future<void> switchProject(WorkspaceSummary target) async {
      await openSidebar(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sidebar-home')));
      await tester.pumpAndSettle();
      await openRecent(tester, workspaceId: target.id);
    }

    await switchProject(otherWorkspace);
    final input = find.byKey(const ValueKey('chat-input'));
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await tester.enterText(input, 'Second project draft');
    await switchProject(workspace);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'First project draft',
    );
    await switchProject(otherWorkspace);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Second project draft',
    );
    expect(gateway.activations, 0);
  });

  testWidgets('returning home discovers projects without choosing a chat', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    gateway.workspaces = [workspace, otherWorkspace];
    await openSidebar(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-home')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-row-ts_002')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    expect(find.text(otherWorkspace.name), findsOneWidget);
    await tester.tap(find.text('Transition-state search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChatPage>(find.byType(ChatPage)).workspace.id,
      'ts_002',
    );
  });

  testWidgets('a stale sidebar response cannot replace a new conversation', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    final delayed = Completer<List<SessionSummary>>();
    gateway.nextSessionList = delayed;
    await openSidebar(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('sidebar-new-session')));
    await tester.pumpAndSettle();
    delayed.complete([session('session_1'), session('session_2')]);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChatPage>(find.byType(ChatPage)).session.sessionId,
      'session_3',
    );
    expect(gateway.creations, 1);
  });

  testWidgets('activation success does not automatically send the draft', (
    tester,
  ) async {
    final gateway = ConversationGateway()
      ..activation = Completer<SessionSummary>();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Review the endpoint',
    );
    await tester.tap(find.byKey(const ValueKey('continue-session')));
    await tester.pump();
    gateway.activation!.complete(
      const SessionSummary(
        sessionId: 'session_1',
        sessionRevision: 'revision-1',
        runtimeState: RuntimeState.idle,
        isStreaming: false,
        accessMode: SessionAccessMode.controller,
        historyAvailable: true,
        canPrompt: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.messageLimits, [50, 50]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(gateway.sent, 0);
    final send = find.byKey(const ValueKey('composer-send'));
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(gateway.sent, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('embedded chat retains manual synchronization and details', (
    tester,
  ) async {
    final gateway = ConversationGateway();
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await tester.tap(find.byKey(const ValueKey('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synchronize messages'));
    await tester.pumpAndSettle();
    expect(gateway.messageLimits.length, 2);
    expect(gateway.activations, 0);
    await tester.tap(find.byKey(const ValueKey('chat-session-details')));
    await tester.pumpAndSettle();
    expect(find.text('session_1'), findsNothing);
    expect(
      find.byKey(const ValueKey('session-runtime-unavailable')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('session-technical-details')));
    await tester.pumpAndSettle();
    expect(find.text('session_1'), findsOneWidget);
  });

  test('activation refreshes the live controller after history', () async {
    final gateway = ConversationGateway();
    final controller = ChatController(
      api: gateway,
      workspaceId: workspace.id,
      sessionId: 'session_1',
      initialSessionRevision: 'revision-1',
      initialRuntimeState: RuntimeState.offline,
      initialHistoryAvailable: true,
      accessMode: SessionAccessMode.controller,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller
        .acceptActivation(
          const SessionSummary(
            sessionId: 'session_1',
            sessionRevision: 'revision-1',
            runtimeState: RuntimeState.idle,
            isStreaming: false,
            accessMode: SessionAccessMode.controller,
            historyAvailable: true,
            canPrompt: true,
          ),
        )
        .timeout(const Duration(seconds: 2));
    expect(gateway.messageLimits, [50, 50]);
    expect(controller.canSend, isTrue);
  });

  testWidgets(
    'activation reads the latest revision and explicitly requests research mode',
    (tester) async {
      final gateway = ConversationGateway();
      await tester.pumpWidget(shellApp(gateway));
      await tester.pumpAndSettle();
      await openRecent(tester);
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Keep this draft',
      );
      gateway.sessions = [
        session('session_1', managementRevision: 'fresh-revision'),
      ];
      await tester.tap(find.byKey(const ValueKey('continue-session')));
      await tester.pumpAndSettle();
      expect(gateway.activatedMode, SessionAccessMode.controller);
      expect(gateway.activatedRevision, 'fresh-revision');
      expect(gateway.activationRequestId, isNotEmpty);
      expect(gateway.sent, 0);
      expect(find.text('Keep this draft'), findsOneWidget);
    },
  );

  testWidgets(
    'switching uses the displayed source revision only after confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = ConversationGateway()
        ..sessions = [
          session(
            'session_1',
            activation: const SessionActivation(
              modes: {SessionAccessMode.controller, SessionAccessMode.observer},
              conflict: SessionActivationConflict(
                sessionId: 'session_2',
                sessionRevision: 'source-revision',
                sessionName: 'Alternative mechanism',
                owner: 'host',
                switchable: true,
              ),
            ),
          ),
        ];
      await tester.pumpWidget(shellApp(gateway));
      await tester.pumpAndSettle();
      await openRecent(tester);
      await tester.tap(find.byKey(const ValueKey('continue-session')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(gateway.activations, 0);
      await capture(tester, 'activation-switch');
      await tester.tap(find.text('Switch').last);
      await tester.pumpAndSettle();
      expect(gateway.activationSource?.sessionRevision, 'source-revision');
      expect(gateway.activations, 1);
    },
  );

  testWidgets('external owner can be opened but never switched', (
    tester,
  ) async {
    final gateway = ConversationGateway()
      ..sessions = [
        session(
          'session_1',
          activation: const SessionActivation(
            modes: {SessionAccessMode.observer},
            conflict: SessionActivationConflict(
              sessionId: 'session_2',
              sessionRevision: 'source-revision',
              sessionName: 'Alternative mechanism',
              owner: 'external',
              switchable: false,
            ),
          ),
        ),
        session('session_2'),
      ];
    await tester.pumpWidget(shellApp(gateway));
    await tester.pumpAndSettle();
    await openRecent(tester);
    await tester.tap(find.byKey(const ValueKey('continue-session')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Switch'), findsNothing);
    await tester.tap(find.text('Open conversation'));
    await tester.pumpAndSettle();
    expect(gateway.activations, 0);
    expect(find.text('Alternative mechanism'), findsWidgets);
  });

  testWidgets(
    'an older Host never silently receives a preference-only research activation',
    (tester) async {
      final gateway = ConversationGateway()
        ..sessions = [session('session_1', capabilities: {}, activation: null)];
      await tester.pumpWidget(shellApp(gateway));
      await tester.pumpAndSettle();
      await openRecent(tester);
      await tester.tap(find.byKey(const ValueKey('continue-session')));
      await tester.pumpAndSettle();
      expect(gateway.activations, 0);
      expect(find.textContaining('Update the TSPi Host'), findsOneWidget);
    },
  );

  for (final locale in ['en', 'zh']) {
    for (final dark in [false, true]) {
      for (final size in [
        const Size(390, 844),
        const Size(320, 740),
        const Size(1100, 800),
      ]) {
        testWidgets('conversation layout $locale $dark ${size.width}', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpWidget(
            shellApp(
              ConversationGateway(),
              locale: Locale(locale),
              dark: dark,
              scale: size.width == 320 ? 2 : 1,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(tester, '$locale-$dark-${size.width}-home');
          await tester.tap(find.byKey(const ValueKey('workspace-settings')));
          await tester.pumpAndSettle();
          await capture(tester, '$locale-$dark-${size.width}-settings');
          final details = find.byKey(
            const ValueKey('connection-details-toggle'),
          );
          await tester.ensureVisible(details);
          await tester.pumpAndSettle();
          await tester.tap(details);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(SelectableText));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('copy-server-address')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capture(tester, '$locale-$dark-${size.width}-settings-details');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await openRecent(tester);
          await capture(tester, '$locale-$dark-${size.width}-chat');
          if (size.width < 900) {
            await openSidebar(tester);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await capture(tester, '$locale-$dark-${size.width}-sidebar');
            Navigator.of(
              tester.element(find.byKey(const ValueKey('conversation-search'))),
            ).pop();
            await tester.pumpAndSettle();
          }
          await tester.enterText(
            find.byKey(const ValueKey('chat-input')),
            locale == 'en'
                ? 'Compare the two candidate pathways.\nCheck the mode assignment and endpoint connectivity.'
                : '比较两条候选反应路径。\n检查虚频模式归属和端点连通性，保留竞争假设。',
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('chat-composer'))).bottom,
            lessThanOrEqualTo(size.height - 280),
          );
          final headerBottom = tester.getRect(find.byType(AppBar)).bottom;
          for (final key in [
            'chat-composer',
            'continue-session',
            'jump-to-start',
            'jump-to-latest',
          ]) {
            final control = find.byKey(ValueKey(key));
            if (control.evaluate().isNotEmpty) {
              expect(
                tester.getRect(control).top,
                greaterThanOrEqualTo(headerBottom),
              );
            }
          }
          expect(tester.takeException(), isNull);
          await capture(tester, '$locale-$dark-${size.width}-keyboard');
        });
      }
    }
  }
}

Future<void> openSidebar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(const ValueKey('chat-menu')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.byKey(const ValueKey('chat-open-sidebar')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> openRecent(
  WidgetTester tester, {
  String workspaceId = 'ts_001',
  String sessionId = 'session_1',
}) async {
  await tester.tap(
    find.byKey(ValueKey('recent-session-$workspaceId-$sessionId')),
  );
  await tester.pumpAndSettle();
}

Future<void> loadPreviewFonts() async {
  if (Platform.environment['TS_PHONE_CAPTURE_UI'] != '1') return;
  final fontPath = Platform.environment['TS_PHONE_PREVIEW_FONT'];
  final iconPath = Platform.environment['TS_PHONE_PREVIEW_ICONS'];
  if (fontPath != null) {
    for (final family in ['Ahem', 'Roboto', 'monospace']) {
      final font = FontLoader(family)
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
  }
  if (iconPath != null) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(File(iconPath).readAsBytes().then(ByteData.sublistView));
    await icons.load();
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['TS_PHONE_CAPTURE_UI'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory('build/conversation-previews').create(recursive: true);
    await File(
      'build/conversation-previews/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

class MemorySelectionStore implements ConversationSelectionStore {
  (String, String) selected = ('ts_001', 'session_2');
  @override
  Future<(String, String)?> loadConversation(String endpoint) async => selected;
  @override
  Future<void> saveConversation(
    String endpoint,
    String workspace,
    String session,
  ) async {
    selected = (workspace, session);
  }
}

class ConversationGateway implements TsPhoneGateway, TsPhoneManagementGateway {
  int activations = 0;
  SessionAccessMode? activatedMode;
  String? activatedRevision;
  String? activationRequestId;
  SessionActivationConflict? activationSource;
  int creations = 0;
  int sent = 0;
  final failedSummaryWorkspaces = <String>{};
  final messageLimits = <int?>[];
  Completer<SessionSummary>? activation;
  Completer<SessionSummary>? creation;
  Completer<List<SessionSummary>>? nextSessionList;
  List<WorkspaceSummary> workspaces = [workspace];
  List<SessionSummary> sessions = [session('session_1'), session('session_2')];
  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaces;
  @override
  Future<List<WorkspaceSummary>> listWorkspacesByLifecycle(
    LifecycleState lifecycle,
  ) async => lifecycle == LifecycleState.active ? workspaces : [];
  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    if (failedSummaryWorkspaces.contains(workspaceId)) {
      throw StateError('summary unavailable');
    }
    return sessions;
  }

  @override
  Future<List<SessionSummary>> listSessionsByLifecycle(
    String workspaceId,
    LifecycleState lifecycle,
  ) async {
    final pending = nextSessionList;
    nextSessionList = null;
    return pending != null
        ? pending.future
        : lifecycle == LifecycleState.active
        ? sessions
        : [];
  }

  @override
  Future<SessionSummary> createSession(
    String workspaceId, {
    required SessionAccessMode accessMode,
    String? name,
    String? model,
  }) async {
    creations++;
    final created =
        await (creation?.future ?? Future.value(session('session_3')));
    sessions = [...sessions, created];
    return created;
  }

  @override
  Future<SessionSummary> activateSession(
    String workspaceId,
    String sessionId,
    String revision, {
    SessionAccessMode? accessMode,
    String? requestId,
    SessionActivationConflict? switchFrom,
  }) {
    activations++;
    activatedMode = accessMode;
    activatedRevision = revision;
    activationRequestId = requestId;
    activationSource = switchFrom;
    return activation?.future ?? Future.value(session(sessionId));
  }

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) async {
    messageLimits.add(limit);
    return TsPhoneMessageSnapshot(
      sessionId: sessionId,
      sessionRevision: 'revision-1',
      messageIds: const ['00000001', '00000002'],
      lastEventId: 'event-1',
      messages: const [
        {
          'role': 'user',
          'content': 'Compare the concerted and stepwise pathways.',
        },
        {
          'role': 'assistant',
          'content':
              '## Candidate pathways\n\nThe concerted pathway remains a hypothesis.\n\nWe will check the imaginary mode and endpoint connectivity before drawing a mechanistic conclusion.',
        },
      ],
    );
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) => StreamController<TsPhoneEvent>(
    onListen: onConnected,
    // Keep cancellation completion in the widget test's asynchronous zone.
    onCancel: () async {},
  ).stream;
  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String revision,
    String message, {
    required String clientMessageId,
  }) async {
    sent++;
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
