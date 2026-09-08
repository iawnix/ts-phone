import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/chat_page.dart';
import 'package:ts_phone/features/chat/model_picker.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/phone_model.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';

import 'chat_controller_test.dart' as fixtures;
import 'conversation_shell_test.dart' as shell;

const first = PhoneModel(
  provider: 'cpa',
  id: 'gpt-5.6-sol',
  name: 'GPT-5.6 Sol',
  contextWindow: 128000,
);
const second = PhoneModel(
  provider: 'cpa',
  id: 'gpt-5.6-terra',
  name: 'GPT-5.6 Terra',
  contextWindow: 64000,
);
const revision = '11111111-1111-4111-8111-111111111111';

SessionSummary ready([PhoneModel model = first]) => SessionSummary(
  sessionId: 'session-test',
  sessionRevision: revision,
  sessionName:
      'Transition-state search with competing hypotheses and endpoint validation',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  accessMode: SessionAccessMode.controller,
  historyAvailable: true,
  capabilities: const {'command.model'},
  runtime: SessionRuntimeSnapshot.fromJson(
    fixtures.sessionRuntimeJson(modelId: model.id, usedTokens: 300),
  ),
);

class ModelGateway extends fixtures.FakeGateway implements TsPhoneModelGateway {
  Completer<SessionSummary>? selection;
  Completer<List<PhoneModel>>? catalog;
  Object? failure;
  int selections = 0;
  List<PhoneModel> available = [first, second];
  @override
  Future<List<PhoneModel>> models() async =>
      catalog == null ? available : await catalog!.future;
  @override
  Future<SessionSummary> selectModel(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    PhoneModel model,
  ) async {
    expect(workspaceId, 'ts_001');
    expect(sessionId, 'session-test');
    expect(sessionRevision, revision);
    selections++;
    if (failure != null) throw failure!;
    return selection == null ? ready(model) : await selection!.future;
  }
}

class RenameGateway extends ModelGateway implements TsPhoneManagementGateway {
  SessionSummary current = ready();
  int renames = 0;

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async => [
    current,
  ];

  @override
  Future<SessionSummary> renameSession(
    String workspaceId,
    String sessionId,
    String managementRevision,
    String name,
  ) async {
    expect(workspaceId, 'ts_001');
    expect(sessionId, current.sessionId);
    expect(managementRevision, current.managementRevision);
    renames++;
    return current = SessionSummary(
      sessionId: current.sessionId,
      sessionRevision: current.sessionRevision,
      sessionName: name,
      managementRevision: 'renamed',
      runtimeState: current.runtimeState,
      isStreaming: current.isStreaming,
      accessMode: current.accessMode,
      capabilities: current.capabilities,
      runtime: current.runtime,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatController controllerFor(
  ModelGateway api, {
  SessionAccessMode access = SessionAccessMode.controller,
}) => ChatController(
  api: api,
  workspaceId: 'ts_001',
  sessionId: 'session-test',
  initialSessionRevision: revision,
  initialRuntimeState: RuntimeState.idle,
  accessMode: access,
  initialCapabilities: const {'command.model'},
  initialSessionRuntime: ready().runtime,
);

void main() {
  setUpAll(shell.loadPreviewFonts);
  test(
    'model changes wait for Host acknowledgement without reloading history',
    () async {
      final api = ModelGateway()..selection = Completer<SessionSummary>();
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.canSelectModel, isTrue);
      final pending = controller.selectModel(second);
      expect(controller.canSelectModel, isFalse);
      expect(await controller.send('must not send'), isFalse);
      expect(controller.sessionRuntime!.model.id, first.id);
      api.selection!.complete(ready(second));
      await pending;
      expect(controller.sessionRuntime!.model.id, second.id);
      expect(controller.canSelectModel, isTrue);
      expect(api.messageSnapshotCalls, 1);
      expect(api.sendCalls, 0);
    },
  );

  test(
    'lost switch receipt blocks commands until a fresh state arrives',
    () async {
      final api = ModelGateway()..failure = TimeoutException('lost receipt');
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      final snapshot = Completer<TsPhoneMessageSnapshot>();
      api.nextSnapshot = snapshot.future;
      final pending = expectLater(
        controller.selectModel(second),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.canSend, isFalse);
      expect(controller.canSelectModel, isFalse);
      snapshot.complete(api.snapshot);
      await pending;
      expect(controller.canSend, isFalse);
      api.addEvent('session_state', {
        'state': 'idle',
        'canPrompt': true,
        'capabilities': ['command.model'],
        'runtime': fixtures.sessionRuntimeJson(
          modelId: second.id,
          usedTokens: null,
        ),
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.sessionRuntime!.model.id, second.id);
      expect(controller.canSend, isTrue);
    },
  );

  test(
    'observer, running, and disconnected sessions cannot select a model',
    () async {
      final api = ModelGateway();
      final controller = controllerFor(api, access: SessionAccessMode.observer);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.canSelectModel, isFalse);
      controller.accessMode = SessionAccessMode.controller;
      api.addEvent('session_state', {
        'state': 'running',
        'activeAgentRunId': 'run_1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.canSelectModel, isFalse);
      api.addEvent('session_state', {
        'state': 'idle',
        'activeAgentRunId': null,
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.canSelectModel, isTrue);
      api.failEventStream();
      await Future<void>.delayed(Duration.zero);
      expect(controller.canSelectModel, isFalse);
      expect(api.selections, 0);
    },
  );

  test(
    'an idle conversation can replace a model with missing authentication',
    () async {
      final api = ModelGateway();
      final controller = controllerFor(api);
      addTearDown(controller.dispose);
      await controller.initialize();
      api.addEvent('session_state', {
        'state': 'idle',
        'canPrompt': false,
        'promptProblem': 'model_auth_missing',
        'capabilities': ['command.model'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.canSend, isFalse);
      expect(controller.canSelectModel, isTrue);
      await controller.selectModel(second);
      expect(controller.canSend, isTrue);
    },
  );

  testWidgets(
    'full title and rename stay in details without replacing the draft or history',
    (tester) async {
      final api = RenameGateway();
      final title = api.current.sessionName!;
      await tester.pumpWidget(
        MaterialApp(
          theme: TsPhoneTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatPage(
            settings: shell.settings,
            workspace: shell.workspace,
            session: api.current,
            gateway: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = tester.widget<Text>(find.text(title));
      expect(heading.maxLines, 1);
      expect(heading.overflow, TextOverflow.ellipsis);
      final input = find.byKey(const ValueKey('chat-input'));
      await tester.enterText(input, 'Keep the next question');
      await tester.tap(find.byKey(const ValueKey('chat-session-details')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, title), findsOneWidget);
      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Endpoint validation',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Endpoint validation'), findsOneWidget);
      expect(api.renames, 1);
      expect(api.messageSnapshotCalls, 1);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Keep the next question',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picker waits for confirmation and leaves the old selection on failure',
    (tester) async {
      final api = ModelGateway()..catalog = Completer<List<PhoneModel>>();
      final receipt = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () => showModelPicker(
                  context,
                  gateway: api,
                  selected: first.reference,
                  onSelect: (_) => receipt.future,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      api.catalog!.complete([first, second]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('model-${second.reference}')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Choose model'), findsOneWidget);
      receipt.completeError(
        const TsPhoneApiException('redacted', code: 'model_unavailable'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose model'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('model-${first.reference}')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model search fits above the keyboard on a narrow screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final api = ModelGateway()
      ..available = List.generate(
        12,
        (index) => PhoneModel(
          provider: 'cpa',
          id: 'model-$index',
          name: 'Model $index with a longer display name',
          contextWindow: 64000,
        ),
      );
    PhoneModel? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showModelPicker(context, gateway: api);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'model-11');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('model-cpa/model-11'));
    expect(find.byKey(const ValueKey('model-cpa/model-0')), findsNothing);
    expect(tester.getRect(result).bottom, lessThanOrEqualTo(360));
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(selected?.id, 'model-11');
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['en', 'zh']) {
    for (final dark in [false, true]) {
      testWidgets(
        'composer model control preserves keyboard and draft: $locale $dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          tester.view.padding = const FakeViewPadding(bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(bottom: 24);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          final api = ModelGateway();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('capture-root'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? TsPhoneTheme.dark() : TsPhoneTheme.light(),
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: ChatPage(
                  settings: shell.settings,
                  workspace: shell.workspace,
                  session: ready(),
                  gateway: api,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await shell.capture(tester, 'model-$locale-$dark-chat');
          final input = find.byKey(const ValueKey('chat-input'));
          await tester.enterText(input, 'Keep this draft');
          final field = tester.widget<TextField>(input);
          field.controller!.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 7,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('chat-composer'))).bottom,
            lessThanOrEqualTo(460),
          );
          final model = find.byKey(const ValueKey('composer-model'));
          expect(tester.getSize(model).height, greaterThanOrEqualTo(44));
          await shell.capture(tester, 'model-$locale-$dark-keyboard');
          await tester.tap(model);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(find.byKey(ValueKey('model-${second.reference}')))
                .bottom,
            lessThanOrEqualTo(716),
          );
          await shell.capture(tester, 'model-$locale-$dark-picker');
          await tester.tap(find.byKey(ValueKey('model-${second.reference}')));
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('model-${second.reference}')),
            findsNothing,
          );
          expect(field.controller!.text, 'Keep this draft');
          expect(
            field.controller!.selection,
            const TextSelection(baseOffset: 2, extentOffset: 7),
          );
          expect(field.focusNode!.hasFocus, isTrue);
          expect(find.text(second.id), findsOneWidget);
          expect(api.messageSnapshotCalls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
