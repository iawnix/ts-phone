import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
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
}
