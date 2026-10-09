import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/widgets/chat_message_view.dart';
import 'package:ts_phone/widgets/ts_phone_brand_mark.dart';
import 'package:ts_phone/widgets/content_display_error.dart';
import 'package:ts_phone/widgets/text_detail_view.dart';

Widget presentation(Widget child) => MaterialApp(
  theme: TsPhoneTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'framework failures remain reported and cannot fill a history page',
    (tester) async {
      final original = ErrorWidget.builder;
      ErrorWidget.builder = (_) => const ContentDisplayError();
      try {
        await tester.pumpWidget(
          presentation(
            Column(
              children: [
                Builder(
                  builder: (_) => throw StateError('fixture-render-failure'),
                ),
                const Text('Next history item'),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isStateError);
        expect(
          find.text('This content could not be displayed.'),
          findsOneWidget,
        );
        expect(tester.getSize(find.byType(ContentDisplayError)).height, 88);
        expect(
          tester.getRect(find.text('Next history item')).bottom,
          lessThan(200),
        );
      } finally {
        ErrorWidget.builder = original;
      }
    },
  );

  testWidgets('full output copy retains text beyond the bounded preview', (
    tester,
  ) async {
    final text = List.generate(2000, (index) => 'Output $index').join('\n');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      presentation(TextDetailPreview(text: text, title: 'Output')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TextDetailPreview)).height,
      lessThan(500),
    );
    await tester.tap(find.byTooltip('View full output'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy full output'));
    await tester.pumpAndSettle();
    expect(copied, text);
    expect(tester.takeException(), isNull);
  });

  for (final (state, text) in [
    (AssistantOutputState.empty, 'No displayable response in this record'),
    (AssistantOutputState.notDisplayed, 'This record has no displayable text'),
    (AssistantOutputState.failed, 'Generation failed'),
    (AssistantOutputState.aborted, 'Generation stopped'),
  ]) {
    testWidgets('empty assistant presents $state without an orphan logo', (
      tester,
    ) async {
      await tester.pumpWidget(
        presentation(
          ChatMessageView(
            message: ChatMessage(
              role: ChatRole.assistant,
              text: '',
              outputState: state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.byType(TsPhoneBrandMark), findsNothing);
      expect(find.text('TSPi'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed output keeps technical detail collapsed by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      presentation(
        ChatMessageView(
          message: const ChatMessage(
            role: ChatRole.assistant,
            text: '',
            outputState: AssistantOutputState.failed,
            failure: ChatFailure(
              code: 'provider_error',
              summary: 'The model service rejected the request',
              detail: "400: Invalid 'tools[1].name'",
              statusCode: 400,
              operationId: 'run-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generation failed'), findsOneWidget);
    expect(
      find.text('The model service rejected the request · HTTP 400'),
      findsOneWidget,
    );
    expect(find.text("400: Invalid 'tools[1].name'"), findsNothing);

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.textContaining("400: Invalid 'tools[1].name'"), findsOneWidget);
  });
}
