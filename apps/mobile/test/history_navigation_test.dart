import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/chat/timeline_widgets.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

import 'chat_controller_test.dart' as fixtures;
import 'conversation_shell_test.dart' as shell;

const revision = '11111111-1111-4111-8111-111111111111';
const capabilities = {timelineCapability, 'history.seek'};

TsPhoneTimelineSnapshot page(
  int start, {
  bool later = false,
  bool details = false,
}) => fixtures.timelineSnapshot(
  items: [
    TimelineMessageItem(
      id: start.toRadixString(16).padLeft(8, '0'),
      turnId: '00000000',
      message: ChatMessage(role: ChatRole.user, text: 'message-$start'),
    ),
    if (details)
      TimelineActivityItem(
        id: '00000001',
        turnId: '00000000',
        activity: TimelineActivity(
          category: TimelineActivityCategory.research,
          status: TimelineActivityStatus.completed,
          title: 'Generate',
          detail: List.generate(2000, (i) => 'Output line $i').join('\n'),
        ),
      ),
  ],
  totalItems: 2108,
  hasMore: start > 0,
  nextBefore: start > 0 ? start.toRadixString(16).padLeft(8, '0') : null,
  hasLater: later,
  nextAfter: later ? '00000001' : null,
  selectedBranchId: '0000083b',
  activeBranchId: '0000083b',
);

ChatController controller(fixtures.FakeGateway api) => ChatController(
  api: api,
  workspaceId: 'ts_001',
  sessionId: 'session-test',
  initialSessionRevision: revision,
  initialRuntimeState: RuntimeState.idle,
  accessMode: SessionAccessMode.observer,
  initialCapabilities: capabilities,
);

void main() {
  test(
    'latest supersedes a slow seek without letting its reply reset the list',
    () async {
      final first = Completer<TsPhoneTimelineSnapshot>();
      final api = fixtures.FakeGateway()
        ..timelineResponder = ({before, branch}) async => page(2107);
      api.timelineWindowResponder =
          ({after, required fromStart, branch, required limit}) => first.future;
      final chat = controller(api);
      addTearDown(chat.dispose);
      await chat.initialize();
      final seeking = chat.jumpToStart();
      expect(chat.historyNavigationInProgress, isTrue);
      expect(await chat.returnToLatest(), isTrue);
      first.complete(page(0, later: true));
      expect(await seeking, isFalse);
      expect(chat.messages.single.text, 'message-2107');
      expect(chat.viewingHistoryWindow, isFalse);
      expect(chat.historyNavigationInProgress, isFalse);
    },
  );

  test(
    'latest ignores an earlier-page error arriving after navigation',
    () async {
      final earlier = Completer<TsPhoneTimelineSnapshot>();
      final api = fixtures.FakeGateway()
        ..timelineResponder = ({before, branch}) =>
            before == null ? Future.value(page(2107)) : earlier.future;
      final chat = controller(api);
      addTearDown(chat.dispose);
      await chat.initialize();
      final loading = chat.loadEarlierMessages();
      expect(await chat.returnToLatest(), isTrue);
      earlier.completeError(const TsPhoneApiException('old failure'));
      expect(await loading, isFalse);
      expect(chat.problem, isNull);
      expect(chat.messages.single.text, 'message-2107');
    },
  );

  test(
    'latest waits for background sync then performs an explicit tail reset',
    () async {
      final api = fixtures.FakeGateway()
        ..timelineResponder = ({before, branch}) async => page(2107);
      api.timelineWindowResponder =
          ({after, required fromStart, branch, required limit}) async =>
              page(0, later: true);
      final chat = controller(api);
      addTearDown(chat.dispose);
      await chat.initialize();
      await chat.jumpToStart();
      final sync = Completer<TsPhoneTimelineSnapshot>();
      var reads = 0;
      api.timelineResponder = ({before, branch}) =>
          ++reads == 1 ? sync.future : Future.value(page(2107));
      final refreshing = chat.refreshMessages();
      final latest = chat.returnToLatest();
      sync.complete(page(2106));
      await refreshing;
      expect(await latest, isTrue);
      expect(reads, 2);
      expect(chat.messages.single.text, 'message-2107');
    },
  );

  test('tail history is independent of old event transport cleanup', () async {
    final cleanup = Completer<void>();
    final api = SlowCancelGateway(cleanup.future)
      ..timelineResponder = ({before, branch}) async => page(2107);
    final chat = controller(api);
    addTearDown(chat.dispose);
    await chat.initialize();
    expect(
      await chat.returnToLatest().timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(chat.messages.single.text, 'message-2107');
    expect(api.eventConnectionCount, 1);
    cleanup.complete();
    await Future<void>.delayed(Duration.zero);
    expect(api.eventConnectionCount, 2);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'start, expanded output, full view, and latest on a phone: dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = fixtures.FakeGateway()
          ..timelineResponder = ({before, branch}) async => page(2107);
        api.timelineWindowResponder =
            ({after, required fromStart, branch, required limit}) async =>
                page(0, later: true, details: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? TsPhoneTheme.dark() : TsPhoneTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatPage(
              settings: shell.settings,
              workspace: shell.appServer,
              gateway: api,
              session: const SessionSummary(
                sessionId: 'session-test',
                sessionRevision: revision,
                runtimeState: RuntimeState.idle,
                isStreaming: false,
                accessMode: SessionAccessMode.observer,
                capabilities: capabilities,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Jump to the start of the session'));
        await tester.pumpAndSettle();
        expect(find.text('message-0'), findsOneWidget);
        final activity = find.byType(TimelineActivityView);
        await tester.ensureVisible(activity);
        await tester.tap(
          find.descendant(of: activity, matching: find.byType(ExpansionTile)),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(activity).height, lessThan(500));
        await tester.ensureVisible(find.byTooltip('View full output'));
        await tester.tap(find.byTooltip('View full output'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('full-output-list')), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jump-to-latest')));
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('message-2107'), findsOneWidget);
        expect(find.text('message-0'), findsNothing);
        expect(find.byKey(const ValueKey('load-later-messages')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keeps a failed sync in the app-bar status control', (
    tester,
  ) async {
    final snapshot = Completer<TsPhoneMessageSnapshot>();
    final api = fixtures.FakeGateway()..nextSnapshot = snapshot.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatPage(
          settings: shell.settings,
          workspace: shell.appServer,
          gateway: api,
          session: const SessionSummary(
            sessionId: 'session-test',
            sessionRevision: revision,
            runtimeState: RuntimeState.idle,
            isStreaming: false,
          ),
        ),
      ),
    );
    snapshot.completeError(
      const TsPhoneApiException('service unavailable', statusCode: 503),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-session-status-button')),
      findsOneWidget,
    );
    expect(find.text('Live synchronization interrupted'), findsNothing);
    expect(find.text('Could not connect to the Pi App Server'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-session-status-button')));
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class SlowCancelGateway extends fixtures.FakeGateway {
  SlowCancelGateway(this.cleanup);
  final Future<void> cleanup;

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) {
    eventConnectionCount += 1;
    return StreamController<TsPhoneEvent>(
      onListen: onConnected,
      onCancel: () => cleanup,
    ).stream;
  }
}
