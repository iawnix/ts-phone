import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/widgets/markdown_message.dart';

void main() {
  testWidgets('HTTPS Markdown images load only after opening the preview', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const MarkdownMessage(
          data: '![reaction plot](https://example.invalid/plot.png)',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'reaction plot'), findsOneWidget);
    expect(find.text('example.invalid'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'reaction plot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('markdown-image-preview-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('markdown-preview-image-0')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('markdown-image-preview-page')),
        matching: find.text('reaction plot'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Open in browser'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('markdown-image-preview-page')),
      findsNothing,
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('non-HTTPS Markdown images remain inert', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const MarkdownMessage(
          data: '![unsafe plot](http://example.invalid/plot.png)',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('[Image: unsafe plot]'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'image preview remains usable with large text on a narrow screen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          const MarkdownMessage(
            data:
                '![A long transition-state reaction-coordinate plot description]'
                '(https://example.invalid/plot.png)',
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(
          TextButton,
          'A long transition-state reaction-coordinate plot description',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byKey(const ValueKey<String>('markdown-image-preview-page')),
        findsOneWidget,
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(CloseButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('multiple HTTPS images retain distinct visible descriptions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const MarkdownMessage(
          data:
              '![reactant](https://example.invalid/reactant.png)\n\n'
              '![product](https://example.invalid/product.png)',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'reactant'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'product'), findsOneWidget);
    expect(find.text('example.invalid'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'product'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('markdown-image-preview-page')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('markdown-image-preview-page')),
        matching: find.text('product'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid image taps open only one preview route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const MarkdownMessage(
          data: '![reaction plot](https://example.invalid/plot.png)',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'reaction plot'),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('markdown-image-preview-page')),
      findsOneWidget,
    );
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('markdown-image-preview-page')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: TsPhoneTheme.light(),
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: appChild!,
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}
