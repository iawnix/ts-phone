import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/features/chat/timeline_widgets.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/widgets/chat_message_view.dart';
import 'package:ts_phone/widgets/ts_phone_brand_mark.dart';

Widget presentation(Widget child) => MaterialApp(
  theme: TsPhoneTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('a stopped activity is not relabeled as a failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      presentation(
        const TimelineTurnGroupView(
          group: TimelineTurnGroup(
            turnId: '00000001',
            number: 1,
            items: [
              TimelineMessageItem(
                id: '00000001',
                message: ChatMessage(
                  role: ChatRole.assistant,
                  text: '',
                  outputState: AssistantOutputState.aborted,
                ),
              ),
              TimelineMessageItem(
                id: '00000002',
                message: ChatMessage(
                  role: ChatRole.assistant,
                  text: '',
                  outputState: AssistantOutputState.empty,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generation stopped'), findsOneWidget);
    expect(find.text('Failed'), findsNothing);
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

  testWidgets(
    'activity folding preserves failure visibility and original order',
    (tester) async {
      const items = <SessionTimelineItem>[
        TimelineMessageItem(
          id: '00000001',
          message: ChatMessage(
            role: ChatRole.user,
            text: 'Inspect the endpoint',
          ),
        ),
        TimelineMessageItem(
          id: '00000002',
          message: ChatMessage(
            role: ChatRole.assistant,
            text: '',
            outputState: AssistantOutputState.failed,
          ),
        ),
        TimelineMessageItem(
          id: '00000003',
          message: ChatMessage(
            role: ChatRole.assistant,
            text: '',
            outputState: AssistantOutputState.empty,
          ),
        ),
        TimelineMessageItem(
          id: '00000004',
          message: ChatMessage(
            role: ChatRole.assistant,
            text: 'The endpoint still needs verification',
          ),
        ),
      ];
      await tester.pumpWidget(
        presentation(
          const TimelineTurnGroupView(
            group: TimelineTurnGroup(
              turnId: '00000001',
              number: 1,
              items: items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 activity records'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Generation failed'), findsNothing);
      expect(find.text('Turn 1'), findsNothing);
      await tester.tap(find.text('2 activity records'));
      await tester.pumpAndSettle();
      expect(find.text('Generation failed'), findsOneWidget);
      expect(
        find.text('No displayable response in this record'),
        findsOneWidget,
      );
      final texts = [
        'Inspect the endpoint',
        'Generation failed',
        'No displayable response in this record',
        'The endpoint still needs verification',
      ];
      for (var i = 1; i < texts.length; i++) {
        expect(
          tester.getTopLeft(find.text(texts[i])).dy,
          greaterThan(tester.getTopLeft(find.text(texts[i - 1])).dy),
        );
      }
      expect(items.length, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
