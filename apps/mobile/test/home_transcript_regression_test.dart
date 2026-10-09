import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/session_notice.dart';
import 'package:ts_phone/features/sessions/session_list_page.dart';
import 'chat_controller_test.dart' as fixtures;
import 'conversation_shell_test.dart' as shell;
import 'history_navigation_test.dart' as ui;

void main() {
  testWidgets('phone home searches sessions', (tester) async {
    final api = shell.ConversationGateway();
    await tester.pumpWidget(shell.shellApp(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-search')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('context-toggle-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('context-search')), 'two');
    await tester.pump();
    expect(find.text('Session one'), findsNothing);
    expect(find.text('Session two'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('context-toggle-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-search')), findsNothing);
    expect(find.text('Session one'), findsOneWidget);
  });
  testWidgets('new session remains in home after returning from chat', (
    tester,
  ) async {
    await tester.pumpWidget(shell.shellApp(shell.ConversationGateway()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('context-new-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-back')));
    await tester.pumpAndSettle();
    expect(find.text('Session new-1'), findsOneWidget);
  });
  testWidgets('large complete transcript jumps to start and latest locally', (
    tester,
  ) async {
    final api = fixtures.FakeGateway()
      ..snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: fixtures.revision,
        messages: List.generate(
          300,
          (i) => fixtures.userMessage('Message $i ${'line\n' * (i % 7)}'),
        ),
        lastEventId: '0',
      );
    await ui.open(tester, api);
    expect(find.textContaining('Message 299'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-jump-to-start')));
    await tester.pumpAndSettle();
    expect(find.text('Message 0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('jump-to-latest')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Message 299'), findsOneWidget);
    expect(api.messageSnapshotCalls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('actionable error stays pinned when transcript is scrolled', (
    tester,
  ) async {
    final api = fixtures.FakeGateway()
      ..sendError = const TsPhoneApiException(
        'rejected',
        code: 'prompt_rejected',
        statusCode: 409,
      )
      ..snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: fixtures.revision,
        messages: List.generate(50, (i) => fixtures.userMessage('History $i')),
        lastEventId: '0',
      );
    await ui.open(tester, api);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'rejected',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byType(SessionNoticeView));
    await tester.drag(
      find.byKey(const ValueKey('chat-transcript')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(SessionNoticeView)), before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('deletion explains permanent removal and uses an error action', (
    tester,
  ) async {
    final api = shell.ConversationGateway();
    await tester.pumpWidget(
      ui.app(
        SessionListPage(
          settings: shell.settings,
          workspace: shell.appServer,
          initialSessions: api.sessions,
          gatewayBuilder: (_) => api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('session-one')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      button.style!.backgroundColor!.resolve({}),
      Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.sessions, hasLength(2));
  });
}
