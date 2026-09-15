import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/settings/settings_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/app_locale_preference.dart';
import 'package:ts_phone/models/app_theme_preference.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/widgets/presentation.dart';
import 'package:ts_phone/widgets/ts_phone_brand_mark.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  for (final copyFails in [false, true]) {
    testWidgets('service address copy reports its actual result: $copyFails', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const serverUrl = 'https://phone.example.test';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (copyFails) throw PlatformException(code: 'unavailable');
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
        _settingsApp(
          locale: const Locale('zh'),
          connection: ConnectionSettings(serverUrl: serverUrl, token: token),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connection-details-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Pi App Server'), findsOneWidget);
      expect(find.text('Endpoint'), findsNothing);
      final copy = find.byKey(const ValueKey('copy-server-address'));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, copyFails ? isNull : serverUrl);
      expect(find.text(copyFails ? '无法复制服务地址' : '已复制服务地址'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings keep connection actions explicit and branding quiet', (
    WidgetTester tester,
  ) async {
    const serverUrl = 'https://tsphone.iawnix.xyz';
    var editCount = 0;

    await tester.pumpWidget(
      _settingsApp(
        connection: ConnectionSettings(serverUrl: serverUrl, token: token),
        onEditConnection: () => editCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('connection-edit-affordance')), findsOne);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('connection-service-endpoint')),
          )
          .data,
      serverUrl,
    );

    await tester.tap(find.byKey(const ValueKey('connection-service-edit')));
    expect(editCount, 1);

    final brand = tester.widget<TsPhoneBrandBadge>(
      find.byType(TsPhoneBrandBadge),
    );
    expect(brand.size, 18);
  });

  testWidgets('preferences remain compact on a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) => widget is TsSegmentedControl),
      findsNothing,
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(
      tester.getSize(find.byType(TsSettingsSection).first).height,
      lessThan(220),
    );
    expect(find.byType(TsContentSurface), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('appearance-setting'))).height,
      inInclusiveRange(48, 84),
    );
    expect(find.text('Dark'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('appearance-setting')));
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection actions use one icon per action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _settingsApp(
        connection: ConnectionSettings(
          serverUrl: 'https://tsphone.iawnix.xyz',
          token: token,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnostics = find.byKey(
      const ValueKey('run-connection-diagnostics'),
    );
    final details = find.byKey(const ValueKey('connection-details-toggle'));
    expect(tester.getSize(diagnostics).height, inInclusiveRange(48, 76));
    expect(tester.getSize(details).height, lessThanOrEqualTo(48));
    expect(find.byIcon(Icons.monitor_heart_outlined), findsNothing);
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text preference rows remain actionable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    AppThemePreference? selectedTheme;

    await tester.pumpWidget(
      _settingsApp(onThemeChanged: (value) async => selectedTheme = value),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) => widget is TsSegmentedControl),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('appearance-setting')));
    await tester.pumpAndSettle();
    final darkChoice = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Dark',
      ),
    );
    expect(darkChoice.properties.checked, isFalse);
    expect(darkChoice.properties.inMutuallyExclusiveGroup, isTrue);
    expect(darkChoice.properties.button, isNull);
    expect(darkChoice.properties.onTap, isNotNull);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(selectedTheme, AppThemePreference.dark);
    expect(tester.takeException(), isNull);
  });

  for (final language in <String>['en', 'zh']) {
    for (final scale in <double>[1, 1.3, 2]) {
      testWidgets('preference choices are readable in $language at ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        AppLocalePreference? selectedLocale;
        await tester.pumpWidget(
          _settingsApp(
            locale: Locale(language),
            onLocaleChanged: (value) async => selectedLocale = value,
          ),
        );
        await tester.pumpAndSettle();
        for (final key in ['appearance-setting', 'language-setting']) {
          final texts = find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Text),
          );
          for (final element in texts.evaluate()) {
            final text = element.widget as Text;
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            final box = tester.getRect(find.byWidget(text));
            expect(box.left, greaterThanOrEqualTo(0));
            expect(box.right, lessThanOrEqualTo(393));
          }
        }
        await tester.tap(find.byKey(const ValueKey('language-setting')));
        await tester.pumpAndSettle();
        final l10n = await AppLocalizations.delegate.load(Locale(language));
        final chinese = find.widgetWithText(ListTile, l10n.languageChinese);
        await tester.ensureVisible(chinese);
        await tester.tap(chinese);
        await tester.pumpAndSettle();
        expect(selectedLocale, AppLocalePreference.zh);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('connection diagnostics report Pi App Server facts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _settingsApp(
        connection: ConnectionSettings(
          serverUrl: 'https://phone.test',
          serverId: '123e4567-e89b-42d3-a456-426614174000',
          token: token,
        ),
        gatewayBuilder: (_) => _DiagnosticGateway(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-connection-diagnostics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('connection-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Pi App Server').last, findsOneWidget);
    expect(find.text('pi-app-server/8'), findsOneWidget);
  });
}

class _DiagnosticGateway implements TsPhoneGateway {
  @override
  Future<Map<String, Object?>> version() async => const {
    'apiVersion': 'pi-app-server/8',
    'serviceVersion': 'Pi App Server',
  };

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in settings diagnostics');
}

Widget _settingsApp({
  Key? key,
  Locale locale = const Locale('en'),
  ConnectionSettings? connection,
  VoidCallback? onEditConnection,
  Future<void> Function(AppThemePreference preference)? onThemeChanged,
  Future<void> Function(AppLocalePreference preference)? onLocaleChanged,
  SettingsGatewayBuilder? gatewayBuilder,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: TsPhoneTheme.light(),
    home: SettingsPage(
      key: key,
      connectionSettings: connection,
      themePreference: AppThemePreference.system,
      localePreference: AppLocalePreference.en,
      onThemeChanged: onThemeChanged ?? (_) async {},
      onLocaleChanged: onLocaleChanged ?? (_) async {},
      onEditConnection: onEditConnection ?? () {},
      onClose: () {},
      gatewayBuilder: gatewayBuilder,
    ),
  );
}
