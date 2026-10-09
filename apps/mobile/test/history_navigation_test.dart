import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corhub/features/chat/chat_composer.dart';
import 'package:corhub/features/chat/chat_page.dart';
import 'package:corhub/features/chat/chat_view_memory.dart';
import 'package:corhub/features/sessions/session_tile.dart';
import 'package:corhub/features/sessions/context_switcher.dart';
import 'package:corhub/l10n/app_localizations.dart';
import 'package:corhub/models/workspace.dart';
import 'package:corhub/theme/corhub_theme.dart';
import 'package:corhub/widgets/markdown_message.dart';
import 'package:corhub/widgets/text_detail_view.dart';
import 'chat_controller_test.dart' as fixtures;
import 'conversation_shell_test.dart' as shell;

const session = SessionSummary(
  sessionId: 'session-test',
  sessionRevision: fixtures.revision,
  sessionName: 'Review conversation',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  historyAvailable: true,
  canPrompt: true,
  accessMode: SessionAccessMode.controller,
);
Widget app(Widget child, {ThemeData? theme, double scale = 1}) => MaterialApp(
  theme: theme ?? CorHubTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
Future<void> open(
  WidgetTester tester,
  fixtures.FakeGateway api, {
  ChatViewMemory? memory,
  ThemeData? theme,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    app(
      ChatPage(
        settings: shell.settings,
        workspace: shell.appServer,
        session: session,
        gateway: api,
        memory: memory,
      ),
      theme: theme,
      scale: scale,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ready status does not claim offline or duplicate Ready', (
    tester,
  ) async {
    await open(tester, fixtures.FakeGateway());
    await tester.tap(find.byKey(const ValueKey('chat-session-status-button')));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(find.textContaining('last synchronized'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
  });
  testWidgets('disconnected drafts keep a visible explanation', (tester) async {
    final api = fixtures.FakeGateway();
    await open(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'keep this draft',
    );
    api.failEventStream();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
    expect(composer.canEdit, isTrue);
    expect(composer.canSend, isFalse);
    expect(composer.hint, isNot('Message'));
    expect(find.byKey(const ValueKey('composer-status')), findsOneWidget);
    expect(composer.controller.text, 'keep this draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('running uses the send slot for Stop until a draft exists', (
    tester,
  ) async {
    final api = fixtures.FakeGateway();
    await open(tester, api);
    api.publish(running: true, turn: 'turn-1', stream: '**live**');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('composer-send')), findsNothing);
    expect(find.byKey(const ValueKey('composer-stop')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-action-slot')),
        matching: find.byKey(const ValueKey('composer-stop')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('streaming-message-text')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const ValueKey('streaming-message-text'))),
      isA<MarkdownMessage>(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'queue next',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('session details can be opened from chat', (tester) async {
    await open(tester, fixtures.FakeGateway());
    await tester.tap(find.byKey(const ValueKey('chat-session-details')));
    await tester.pumpAndSettle();
    expect(find.text('session-test'), findsOneWidget);
    expect(find.text('Copy session ID'), findsOneWidget);
  });
  testWidgets('the navigation base remains the home while chat is open', (
    tester,
  ) async {
    final api = shell.ConversationGateway();
    await tester.pumpWidget(shell.shellApp(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session one'));
    await tester.pumpAndSettle();
    expect(
      find.byType(ContextSwitcherSheet, skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('chat-back')));
    await tester.pumpAndSettle();
    expect(find.byType(ContextSwitcherSheet), findsOneWidget);
  });
  testWidgets('session rows remain at least 48 dp with dates and large text', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SessionTile(
              session: SessionSummary(
                sessionId: 'dated',
                sessionRevision: 'r',
                sessionName: 'Dated session',
                runtimeState: RuntimeState.offline,
                isStreaming: false,
                updatedAt: DateTime(2026, 10, 9),
              ),
              onTap: () {},
            ),
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('short output has direct copy but no redundant expand', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: TextDetailPreview(text: 'short output', title: 'Output'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('View full output'), findsNothing);
    expect(find.byTooltip('Copy full output'), findsOneWidget);
  });
  for (final dark in [false, true]) {
    testWidgets('chat fits large text with keyboard, dark=$dark', (
      tester,
    ) async {
      await open(
        tester,
        fixtures.FakeGateway(),
        theme: dark ? CorHubTheme.dark() : CorHubTheme.light(),
        scale: 2,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'draft\nsecond line\nthird line',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  test('input boundary has 3:1 contrast in all themes', () {
    for (final theme in [
      CorHubTheme.light(),
      CorHubTheme.dark(),
      CorHubTheme.highContrastLight(),
      CorHubTheme.highContrastDark(),
    ]) {
      final a = theme.colorScheme.outline.computeLuminance();
      final b = theme.colorScheme.surfaceContainerHigh.computeLuminance();
      expect(
        (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
        greaterThanOrEqualTo(3),
      );
    }
  });
}
