import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/theme/ts_visual_accessibility.dart';
import 'package:ts_phone/widgets/presentation.dart';

void main() {
  testWidgets('glass app bar uses one surface and standard icon targets', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: Scaffold(
          appBar: TsGlassAppBar(
            leading: IconButton(
              key: const ValueKey<String>('leading-action'),
              onPressed: () {},
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('Research'),
            actions: <Widget>[
              IconButton(
                key: const ValueKey<String>('trailing-action'),
                onPressed: () {},
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

    final appBar = find.byType(TsGlassAppBar);
    expect(
      find.descendant(of: appBar, matching: find.byType(TsGlassSurface)),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    for (final key in <String>['leading-action', 'trailing-action']) {
      final size = tester.getSize(find.byKey(ValueKey<String>(key)));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass app bar remains bounded at accessibility text sizes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: const Scaffold(
          appBar: TsGlassAppBar(title: Text('Research workspace')),
          body: SizedBox.expand(),
        ),
      ),
    );

    final title = find.text('Research workspace');
    final appBar = find.byType(AppBar);
    expect(
      tester.getRect(title).height,
      lessThan(tester.getRect(appBar).height),
    );
    expect(MediaQuery.textScalerOf(tester.element(title)).scale(1), 1.34);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'glass app bar adds a stronger scrim after content scrolls under',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TsPhoneTheme.light(),
          home: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: const TsGlassAppBar(title: Text('Research')),
            body: ListView(children: const <Widget>[SizedBox(height: 1200)]),
          ),
        ),
      );

      Material appBarMaterial() => tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppBar),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(appBarMaterial().color, Colors.transparent);

      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TsGlassAppBar));
      expect(
        appBarMaterial().color,
        TsPhoneGlassTheme.resolve(context).elevatedSurface,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduce transparency replaces glass with an opaque surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: const TsVisualAccessibility(
          reduceTransparency: true,
          child: Scaffold(
            appBar: TsGlassAppBar(title: Text('Research')),
            body: Center(
              child: TsGlassSurface(
                elevated: true,
                child: SizedBox.square(dimension: 44),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary content remains opaque', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: const Scaffold(
          body: TsContentSurface(child: SizedBox.square(dimension: 44)),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final decoration = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final boxDecoration = decoration.decoration as BoxDecoration;
    expect(boxDecoration.color?.a, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared segmented control has one unambiguous selection', (
    WidgetTester tester,
  ) async {
    var selected = 'all';
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: TsSegmentedControl<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'all', label: Text('All')),
                ButtonSegment<String>(
                  value: 'activity',
                  label: Text('Activity'),
                ),
              ],
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .showSelectedIcon,
      isFalse,
    );
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(selected, 'activity');
    expect(tester.takeException(), isNull);
  });

  testWidgets('info band stacks its action without truncating large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: TsInfoBand(
            icon: Icons.info_outline,
            message: 'A complete recovery message remains available.',
            action: TextButton(onPressed: () {}, child: const Text('Retry')),
          ),
        ),
      ),
    );

    final message = find.text('A complete recovery message remains available.');
    expect(
      tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
      false,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('semantic foreground colors meet normal-text contrast', () {
    for (final theme in <ThemeData>[
      TsPhoneTheme.light(),
      TsPhoneTheme.dark(),
      TsPhoneTheme.highContrastLight(),
      TsPhoneTheme.highContrastDark(),
    ]) {
      final colors = theme.colorScheme;
      final status = theme.extension<TsPhoneStatusTheme>()!;
      for (final pair in <(Color, Color)>[
        (colors.primary, colors.surface),
        (colors.onSurfaceVariant, colors.surface),
        (colors.onPrimary, colors.primary),
        (status.connected, colors.surface),
        (status.onConnected, status.connected),
        (status.warning, colors.surface),
        (status.onWarning, status.warning),
        (status.error, colors.surface),
        (status.onError, status.error),
        (status.onConnectedContainer, status.connectedContainer),
        (status.onWarningContainer, status.warningContainer),
        (status.onErrorContainer, status.errorContainer),
      ]) {
        expect(
          _contrastRatio(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason:
              '${pair.$1.toARGB32().toRadixString(16)} on '
              '${pair.$2.toARGB32().toRadixString(16)}',
        );
      }
    }
  });

  test('high contrast controls keep opaque, visible boundaries', () {
    for (final theme in <ThemeData>[
      TsPhoneTheme.highContrastLight(),
      TsPhoneTheme.highContrastDark(),
    ]) {
      final colors = theme.colorScheme;
      final inputBorder = theme.inputDecorationTheme.enabledBorder!;
      expect(inputBorder.borderSide.color.a, 1);
      expect(
        _contrastRatio(
          inputBorder.borderSide.color,
          colors.surfaceContainerLowest,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(theme.dividerTheme.color?.a, 1);
    }
  });

  test('transient overlays share the app surface language', () {
    for (final theme in <ThemeData>[
      TsPhoneTheme.light(),
      TsPhoneTheme.dark(),
    ]) {
      final colors = theme.colorScheme;
      expect(theme.dialogTheme.backgroundColor, colors.surfaceContainerLowest);
      expect(
        theme.bottomSheetTheme.modalBackgroundColor,
        colors.surfaceContainerLowest,
      );
      expect(theme.bottomSheetTheme.showDragHandle, isFalse);
      expect(theme.popupMenuTheme.color, colors.surfaceContainerLowest);
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
      expect(theme.popupMenuTheme.surfaceTintColor, Colors.transparent);
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
