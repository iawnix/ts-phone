import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/chat/command_queue_sheet.dart';
import 'package:ts_phone/features/chat/session_view_state.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/phone_model.dart';
import 'package:ts_phone/models/queued_command.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

import 'model_selection_test.dart' as model;
import 'conversation_shell_test.dart' as shell;

class QueueGateway extends model.ModelGateway implements TsPhoneQueueGateway {
  int enqueues = 0;
  int nextModels = 0;
  int cancellations = 0;
  int acknowledgements = 0;
  bool loseReceipt = false;
  bool loseModelReceipt = false;
  bool failMetadata = false;
  String? queuedId;
  List<QueuedCommand> commands = [];
  SessionSummary get current => SessionSummary(
    sessionId: 'session-test',
    sessionRevision: model.revision,
    runtimeState: RuntimeState.offline,
    isStreaming: false,
    accessMode: SessionAccessMode.observer,
    canPrompt: false,
    canActivate: true,
    historyAvailable: true,
    historyOnly: true,
    capabilities: const {'command.queue', 'session.activate_mode'},
    commands: commands,
    nextModel: nextModels == 0 ? model.first.reference : model.second.reference,
  );
  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    if (failMetadata) throw TimeoutException('Host metadata unavailable');
    return [current];
  }

  @override
  Future<QueuedCommand> enqueueMessage(
    String workspaceId,
    String sessionId,
    String revision,
    String message,
    String clientMessageId,
  ) async {
    enqueues++;
    queuedId = clientMessageId;
    commands = [
      QueuedCommand(
        id: clientMessageId,
        sessionId: sessionId,
        status: CommandStatus.queued,
        createdAt: DateTime.now(),
        preview: message,
        position: 1,
      ),
    ];
    if (loseReceipt) throw TimeoutException('Lost HTTP response');
    return commands.single;
  }

  @override
  Future<QueuedCommand> commandReceipt(
    String workspaceId,
    String sessionId,
    String revision,
    String clientMessageId,
  ) async => commands.single;
  @override
  Future<void> cancelQueuedCommand(
    String workspaceId,
    String sessionId,
    String id,
  ) async {
    cancellations++;
    commands = [];
  }

  @override
  Future<void> acknowledgeQueuedCommand(
    String workspaceId,
    String sessionId,
    String id,
  ) async {
    acknowledgements++;
    commands = [];
  }

  @override
  Future<SessionSummary> selectNextModel(
    String workspaceId,
    String sessionId,
    String revision,
    PhoneModel model,
  ) async {
    nextModels++;
    if (loseModelReceipt) throw TimeoutException('Lost model receipt');
    return current;
  }
}

ChatController controllerFor(QueueGateway api) => ChatController(
  api: api,
  workspaceId: 'ts_001',
  sessionId: 'session-test',
  initialSessionRevision: model.revision,
  initialRuntimeState: RuntimeState.offline,
  accessMode: SessionAccessMode.observer,
  initialSession: api.current,
);

void main() {
  setUpAll(shell.loadPreviewFonts);

  test(
    'offline history sends to Host queue without a live snapshot or legacy prompt',
    () async {
      final api = QueueGateway();
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.canSend, isTrue);
      expect(SessionViewState.fromController(controller).canCompose, isTrue);
      expect(SessionViewState.fromController(controller).isHistorical, isFalse);
      expect(await controller.send('Next question'), isTrue);
      expect(api.enqueues, 1);
      expect(api.sendCalls, 0);
      expect(controller.outbox.messages, isEmpty);
      expect(controller.queuedCommands.single.preview, 'Next question');
    },
  );

  test(
    'lost queue receipt is reconciled read-only without resending',
    () async {
      final api = QueueGateway()..loseReceipt = true;
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(await controller.send('Only once'), isTrue);
      expect(api.enqueues, 1);
      expect(controller.outbox.messages, isEmpty);
    },
  );

  test(
    'running conversation can select a model for the next message',
    () async {
      final api = QueueGateway();
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      api.snapshot = TsPhoneMessageSnapshot(
        sessionId: 'session-test',
        sessionRevision: model.revision,
        messages: const [],
        lastEventId: 'epoch:0',
        activeAgentRunId: 'run-1',
      );
      api.addEvent('session_state', {
        'state': 'running',
        'activeAgentRunId': 'run-1',
        'canPrompt': true,
        'capabilities': ['command.queue'],
        'nextModel': model.first.reference,
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.activeAgentRunId, 'run-1');
      expect(controller.canSelectModel, isTrue);
      await controller.selectModel(model.second);
      expect(api.nextModels, 1);
      expect(api.selections, 0);
      expect(controller.selectedModelReference, model.second.reference);
    },
  );

  test(
    'lost model selection reconciles Host preference before another send',
    () async {
      final api = QueueGateway()..loseModelReceipt = true;
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      await expectLater(
        controller.selectModel(model.second),
        throwsA(isA<TimeoutException>()),
      );
      expect(controller.selectedModelReference, model.second.reference);
      expect(controller.canSend, isTrue);
      expect(api.nextModels, 1);
    },
  );

  test(
    'unconfirmed preference blocks send until authoritative metadata returns',
    () async {
      final api = QueueGateway()..loseModelReceipt = true;
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      api.failMetadata = true;
      await expectLater(
        controller.selectModel(model.second),
        throwsA(isA<TimeoutException>()),
      );
      expect(controller.canSend, isFalse);
      expect(controller.canSelectModel, isFalse);
      api.failMetadata = false;
      await controller.refreshSessionMetadata();
      expect(controller.selectedModelReference, model.second.reference);
      expect(controller.canSend, isTrue);
      expect(api.enqueues, 0);
    },
  );

  test(
    'queue recovery indicator clears on a subsequent Host state event',
    () async {
      final api = QueueGateway();
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      api.addEvent('session_state', {
        'state': 'offline',
        'capabilities': ['command.queue'],
        'queueProblem': 'queue_recovery_required',
        'commands': [],
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.queueProblem, 'queue_recovery_required');
      api.addEvent('session_state', {
        'state': 'offline',
        'capabilities': ['command.queue'],
        'queueProblem': null,
        'commands': [],
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.queueProblem, isNull);
    },
  );

  for (final locale in ['en', 'zh']) {
    for (final dark in [false, true]) {
      testWidgets(
        'queued chat and request sheet fit narrow screens: $locale $dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final api = QueueGateway()
            ..commands = [
              QueuedCommand(
                id: 'run',
                sessionId: 'session-other',
                status: CommandStatus.running,
                createdAt: DateTime.now(),
                preview: 'Endpoint optimization',
                model: model.first.reference,
              ),
              QueuedCommand(
                id: 'wait',
                sessionId: 'session-test',
                status: CommandStatus.queued,
                createdAt: DateTime.now(),
                preview:
                    'Check the reaction-coordinate assignment and both endpoints',
                position: 2,
                model: model.second.reference,
              ),
            ];
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('capture-root'),
              child: MaterialApp(
                locale: Locale(locale),
                theme: dark ? TsPhoneTheme.dark() : TsPhoneTheme.light(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.2)),
                  child: child!,
                ),
                home: ChatPage(
                  settings: shell.settings,
                  workspace: shell.workspace,
                  session: api.current,
                  gatewayFactory: () => api,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await shell.capture(
            tester,
            'queued-chat-$locale-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.byKey(const ValueKey('command-queue')));
          await tester.pumpAndSettle();
          expect(find.text('Endpoint optimization'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await shell.capture(
            tester,
            'request-sheet-$locale-${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }

  testWidgets(
    'unified chat has a composer and no mode switch or activation button',
    (tester) async {
      final api = QueueGateway();
      await tester.pumpWidget(
        MaterialApp(
          theme: TsPhoneTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatPage(
            settings: shell.settings,
            workspace: shell.workspace,
            session: api.current,
            gatewayFactory: () => api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('continue-session')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Conversation mode'), findsNothing);
    },
  );

  testWidgets(
    'queue lists waiting requests and cancel is a functional icon action',
    (tester) async {
      final api = QueueGateway();
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.send('Check the endpoint');
      await tester.pumpWidget(
        MaterialApp(
          theme: TsPhoneTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: IconButton(
                onPressed: () => showCommandQueue(context, controller),
                icon: const Icon(Icons.playlist_play),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('Check the endpoint'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel waiting request'));
      await tester.pumpAndSettle();
      expect(api.cancellations, 1);
      expect(find.text('No pending requests'), findsOneWidget);
    },
  );
}
