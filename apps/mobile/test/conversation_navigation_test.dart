import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_composer.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/chat_outbox.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/chat/chat_view_memory.dart';
import 'package:ts_phone/features/sessions/session_list_page.dart';
import 'package:ts_phone/features/workspaces/workspace_list_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/models/chat_message.dart';

import 'conversation_shell_test.dart' as fixtures;

const readySession = SessionSummary(
  sessionId: 'session_1',
  sessionName: 'Transition-state search',
  sessionRevision: 'revision-1',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  historyAvailable: true,
  canPrompt: true,
);

class ReceiptGateway extends fixtures.ConversationGateway {
  Completer<void>? response;
  TsPhoneMessageSnapshot? snapshot;
  int closes = 0;
  final requests = <String>[];

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) async =>
      snapshot ??
      await super.getMessages(
        workspaceId,
        sessionId,
        before: before,
        limit: limit,
      );

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String revision,
    String message, {
    required String clientMessageId,
  }) async {
    requests.add(clientMessageId);
    await response?.future;
    sent++;
  }

  @override
  void close() => closes++;
}

class ApprovalGateway extends ReceiptGateway {
  final feed = StreamController<TsPhoneEvent>.broadcast();
  final decisions = <bool>[];

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) {
    scheduleMicrotask(() => onConnected?.call());
    return feed.stream;
  }

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async => decisions.add(approved);
}

ChatController controller(ReceiptGateway gateway, ChatOutbox outbox) =>
    ChatController(
      api: gateway,
      workspaceId: 'ts_001',
      sessionId: 'session_1',
      initialSessionRevision: 'revision-1',
      initialRuntimeState: RuntimeState.idle,
      accessMode: SessionAccessMode.controller,
      initialCanPrompt: true,
      outbox: outbox,
    );

void main() {
  testWidgets('recent conversation returns home with toolbar and system back', (
    tester,
  ) async {
    final gateway = fixtures.ConversationGateway();
    await tester.pumpWidget(fixtures.shellApp(gateway));
    await tester.pumpAndSettle();
    for (final toolbar in [true, false]) {
      await fixtures.openRecent(tester);
      if (toolbar) {
        await tester.tap(find.byKey(const ValueKey('chat-back')));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsNothing);
      expect(find.byType(WorkspaceListPage), findsOneWidget);
      expect(find.byType(SessionListPage), findsNothing);
    }
  });

  testWidgets(
    'iOS edge back can be cancelled and completed without opening the drawer',
    (tester) async {
      final gateway = fixtures.ConversationGateway();
      await tester.pumpWidget(fixtures.shellApp(gateway));
      await tester.pumpAndSettle();
      await fixtures.openRecent(tester);
      final cancel = await tester.startGesture(const Offset(1, 250));
      await cancel.moveBy(const Offset(45, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-home')), findsNothing);
      await tester.dragFrom(const Offset(1, 250), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsNothing);
      expect(find.byType(WorkspaceListPage), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('back closes an explicitly opened drawer without leaving chat', (
    tester,
  ) async {
    final gateway = fixtures.ConversationGateway();
    await tester.pumpWidget(fixtures.shellApp(gateway));
    await tester.pumpAndSettle();
    await fixtures.openRecent(tester);
    await tester.tap(find.byTooltip('Projects and conversations'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-home')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-home')), findsNothing);
  });

  testWidgets('touching send keeps input focus through pointer down and up', (
    tester,
  ) async {
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: text,
              focusNode: focus,
              canEdit: true,
              canSend: true,
              sending: false,
              maxLines: 5,
              hint: 'Message',
              onSend: () => sends++,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'hello');
    await tester.pumpAndSettle();
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('composer-send'))),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await touch.up();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(sends, 1);
  });

  testWidgets(
    'nested system back defers approval without dropping the request',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = ApprovalGateway()..sessions = [readySession];
      addTearDown(gateway.feed.close);
      await tester.pumpWidget(fixtures.shellApp(gateway));
      await tester.pumpAndSettle();
      await fixtures.openRecent(tester);
      gateway.feed.add(
        TsPhoneEvent(
          id: 'event-2',
          workspaceId: 'ts_001',
          sessionId: 'session_1',
          sessionRevision: 'revision-1',
          instanceEpoch: 'instance-1',
          sessionGeneration: 1,
          type: 'approval.request',
          payload: {
            'id': 'approval-1',
            'method': 'confirm',
            'toolName': 'bash',
            'preview': 'Tool: bash',
            'turnId': 'turn-1',
            'toolCallId': 'tool-1',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
          at: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approval-reject')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(gateway.decisions, isEmpty);
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-approvals')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pending-approvals')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approval-reject')));
      await tester.pumpAndSettle();
      expect(gateway.decisions, [false]);
    },
  );

  for (final rejected in [false, true]) {
    testWidgets(
      'late send receipt after returning and reopening: rejected=$rejected',
      (tester) async {
        final gateway = ReceiptGateway()
          ..sessions = [readySession]
          ..response = Completer<void>();
        await tester.pumpWidget(fixtures.shellApp(gateway));
        await tester.pumpAndSettle();
        await fixtures.openRecent(tester);
        await tester.enterText(
          find.byKey(const ValueKey('chat-input')),
          'one research request',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('composer-send')));
        await tester.pump();
        expect(gateway.requests, hasLength(1));
        await tester.tap(find.byKey(const ValueKey('chat-back')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('recent-session-ts_001-session_1')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (rejected) {
          gateway.response!.completeError(
            const TsPhoneApiException(
              'rejected',
              code: 'model_auth_missing',
              statusCode: 409,
            ),
          );
        } else {
          gateway.response!.complete();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('chat-input')))
              .controller!
              .text,
          rejected ? 'one research request' : '',
        );
        expect(gateway.requests, hasLength(1));
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'pending transport survives controller disposal; uncertain retry retains identity',
    () async {
      final outbox = ChatOutbox();
      final gateway = ReceiptGateway()..response = Completer<void>();
      final first = controller(gateway, outbox);
      await first.initialize();
      final send = first.send('same request');
      first.dispose();
      expect(gateway.closes, 0);
      gateway.response!.completeError(
        const TsPhoneApiException(
          'uncertain',
          code: 'command_ambiguous',
          statusCode: 409,
        ),
      );
      expect(await send, isFalse);
      expect(gateway.closes, 1);
      expect(outbox.uncertain('same request'), isNotNull);
      final nextGateway = ReceiptGateway();
      final next = controller(nextGateway, outbox);
      await next.initialize();
      expect(await next.send('same request'), isTrue);
      expect(nextGateway.requests.single, gateway.requests.single);
      next.dispose();
    },
  );

  test('a later draft is not overwritten by an older rejected send', () {
    final memory = ChatViewMemory()..draft = 'old';
    final revision = memory.takeDraft();
    memory.draft = 'new';
    memory.restoreDraft('old', revision);
    expect(memory.draft, 'new');
  });

  test(
    'delivery warning follows receipts without clearing another error',
    () async {
      final outbox = ChatOutbox();
      final gateway = ReceiptGateway();
      final chat = controller(gateway, outbox);
      addTearDown(chat.dispose);
      await chat.initialize();
      final outgoing = OutgoingChatMessage(
        revision: 'revision-1',
        id: 'pending',
        text: 'first request',
      );
      outbox.begin(outgoing);
      outbox.finish(outgoing, sent: false, uncertain: true);
      expect(chat.problem?.code, TsPhoneProblemCode.deliveryUncertain);
      outbox.receive('revision-1', outgoing.id, preflightAccepted: true);
      expect(chat.problem, isNull);

      gateway.response = Completer<void>();
      final rejected = chat.send('another request');
      gateway.response!.completeError(
        const TsPhoneApiException(
          'model unavailable',
          code: 'model_auth_missing',
          statusCode: 409,
        ),
      );
      expect(await rejected, isFalse);
      outbox.receive('revision-1', outgoing.id, preflightAccepted: true);
      expect(chat.problem?.code, TsPhoneProblemCode.modelAuthMissing);
    },
  );

  for (final changed in [false, true]) {
    test(
      'retry reconciles the exact revision before sending: changed=$changed',
      () async {
        final outbox = ChatOutbox();
        final gateway = ReceiptGateway();
        final chat = controller(gateway, outbox);
        addTearDown(chat.dispose);
        await chat.initialize();
        final outgoing = OutgoingChatMessage(
          revision: 'revision-1',
          id: 'pending',
          text: 'same request',
        );
        outbox.begin(outgoing);
        outbox.finish(outgoing, sent: false, uncertain: true);
        gateway.snapshot = TsPhoneMessageSnapshot(
          sessionId: 'session_1',
          sessionRevision: changed ? 'revision-2' : 'revision-1',
          lastEventId: 'event-2',
          messageIds: const ['00000003'],
          messages: const [
            {
              'role': 'user',
              'content': 'same request',
              'clientMessageId': 'pending',
            },
          ],
        );
        expect(await chat.send('same request'), !changed);
        expect(gateway.requests, isEmpty);
        expect(outbox.accepted(outgoing), !changed);
        expect(
          chat.problem?.code,
          changed ? TsPhoneProblemCode.deliveryUncertain : null,
        );
        expect(
          chat.messages.where((value) => value.deliveryState != null),
          isEmpty,
        );
      },
    );
  }

  test(
    'matching history only clears an acknowledged echo, not uncertain delivery',
    () {
      final outbox = ChatOutbox();
      final sent = OutgoingChatMessage(
        revision: 'revision-1',
        id: 'sent',
        text: 'same',
      );
      final unknown = OutgoingChatMessage(
        revision: 'revision-1',
        id: 'unknown',
        text: 'same',
      );
      outbox.begin(sent);
      outbox.finish(sent, sent: true);
      outbox.begin(unknown);
      outbox.finish(unknown, sent: false, uncertain: true);
      outbox.reconcile('revision-1', [
        ChatMessage(
          role: ChatRole.user,
          text: 'same',
          timestamp: DateTime.now().add(const Duration(milliseconds: 1)),
        ),
      ]);
      expect(outbox.messages.single.id, 'unknown');
      expect(outbox.accepted(unknown), isFalse);
      expect(outbox.accepted(sent), isTrue);
    },
  );

  testWidgets(
    'uncertain message has an explicit retry with the same request ID',
    (tester) async {
      final gateway = ReceiptGateway()
        ..sessions = [readySession]
        ..response = Completer<void>();
      await tester.pumpWidget(fixtures.shellApp(gateway));
      await tester.pumpAndSettle();
      await fixtures.openRecent(tester);
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'uncertain request',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      gateway.response!.completeError(
        const TsPhoneApiException(
          'uncertain',
          code: 'command_ambiguous',
          statusCode: 409,
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.requests, hasLength(1));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        isEmpty,
      );
      gateway.response = null;
      await tester.tap(find.byKey(const ValueKey('retry-message')));
      await tester.pumpAndSettle();
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.toSet(), hasLength(1));
      expect(find.byKey(const ValueKey('retry-message')), findsNothing);
    },
  );
}
