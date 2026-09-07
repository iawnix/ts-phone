import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  testWidgets('connection details show the actual Host version', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsApp(
        connection: ConnectionSettings(
          serverUrl: 'https://phone.test',
          token: token,
        ),
        gatewayBuilder: (settings) => TsPhoneApi(
          settings,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'apiVersion': 'ts-phone-api/4',
                'data': {
                  'apiVersion': 'ts-phone-api/4',
                  'serviceVersion': '0.6.0',
                },
              }),
              200,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-connection-diagnostics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('connection-details-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Server version'));
    expect(find.text('0.6.0'), findsOneWidget);
  });

  testWidgets('diagnostics ignore results from a previous connection', (
    WidgetTester tester,
  ) async {
    final oldResponse = Completer<http.Response>();
    final oldClient = MockClient((_) => oldResponse.future);
    final newClient = MockClient(
      (_) async => http.Response(
        '{"apiVersion":"ts-phone-api/4","data":{"apiVersion":"ts-phone-api/4"}}',
        200,
      ),
    );
    final oldConnection = ConnectionSettings(
      serverUrl: 'https://old.example.test',
      token: token,
    );
    final newConnection = ConnectionSettings(
      serverUrl: 'https://new.example.test',
      token: token,
    );

    await tester.pumpWidget(
      _settingsApp(
        key: const ValueKey('settings-app'),
        connection: oldConnection,
        gatewayBuilder: (settings) => TsPhoneApi(settings, client: oldClient),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-connection-diagnostics')));
    await tester.pump();
    expect(find.text('Checking'), findsOneWidget);

    await tester.pumpWidget(
      _settingsApp(
        key: const ValueKey('settings-app'),
        connection: newConnection,
        gatewayBuilder: (settings) => TsPhoneApi(settings, client: newClient),
      ),
    );
    oldResponse.complete(
      http.Response(
        '{"apiVersion":"ts-phone-api/4","data":{"apiVersion":"ts-phone-api/4"}}',
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Healthy'), findsNothing);
    expect(find.text('Not checked'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('run-connection-diagnostics')));
    await tester.pumpAndSettle();
    expect(find.text('Healthy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics settle when gateway setup or close fails', (
    WidgetTester tester,
  ) async {
    final connection = ConnectionSettings(
      serverUrl: 'https://tsphone.iawnix.xyz',
      token: token,
    );

    await tester.pumpWidget(
      _settingsApp(
        connection: connection,
        gatewayBuilder: (_) => throw StateError('setup failed'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-connection-diagnostics')));
    await tester.pumpAndSettle();
    expect(find.text('Issue'), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-spinner')), findsNothing);

    await tester.pumpWidget(
      _settingsApp(
        connection: connection,
        gatewayBuilder: (settings) =>
            TsPhoneApi(settings, client: _ThrowingCloseClient()),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('run-connection-diagnostics')));
    await tester.pumpAndSettle();
    expect(find.text('Healthy'), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-spinner')), findsNothing);
    expect(tester.takeException(), isNull);
  });
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

class _ThrowingCloseClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.encode(
      '{"apiVersion":"ts-phone-api/4","data":{"apiVersion":"ts-phone-api/4"}}',
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }

  @override
  void close() => throw StateError('close failed');
}
