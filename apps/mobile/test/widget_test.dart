import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ts_phone/app.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/data/settings_store.dart';
import 'package:ts_phone/features/connection/connection_page.dart';
import 'package:ts_phone/features/settings/settings_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/app_theme_preference.dart';
import 'package:ts_phone/models/app_locale_preference.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/widgets/chat_message_view.dart';
import 'package:ts_phone/widgets/markdown_message.dart';
import 'package:ts_phone/widgets/presentation.dart';
import 'package:ts_phone/widgets/ts_phone_brand_mark.dart';

void main() {
  testWidgets('shows the connection screen without layout overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TsPhoneApp(settingsStore: MemorySettingsStore()));
    await tester.pumpAndSettle();

    expect(find.text('TS Phone'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('访问令牌'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.byType(TsPhoneBrandMark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders GFM and TeX content', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownMessage(
              data:
                  '# Result\n\n- [x] done\n\n| A | B |\n|---|---|\n|1|2|\n\n'
                  r'Inline $E=mc^2$.'
                  '\n\n\$\$\n\\Delta G^\\ddagger = 12.3\n\$\$',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byType(Table), findsWidgets);
    expect(find.byType(Math), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not fetch remote Markdown images automatically', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownMessage(
            data: '![reaction plot](https://example.invalid/plot.png)',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders inline code chips and terminal code blocks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: const Scaffold(
          body: MarkdownMessage(
            data: 'Run `claim_2` next.\n\n```sh\nrecalculation complete\n```',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('claim_2'), findsOneWidget);
    expect(find.byType(TsTerminalBlock), findsOneWidget);
    expect(find.text('recalculation complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a complete long tool name without ellipsis', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const toolName = 'ts_workspace_decision_draft';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ChatMessageView(
            message: ChatMessage(
              role: ChatRole.assistant,
              text: '',
              tools: <ToolDetail>[
                ToolDetail(title: toolName, body: '{"valid": true}'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(toolName));
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
    expect(find.text('就绪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changes and restores the global theme from settings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..value = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('tsphone.iawnix.xyz'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(store.themePreference, AppThemePreference.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('connection settings uses standard back navigation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..value = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TS Phone 服务'));
    await tester.pumpAndSettle();

    expect(find.text('连接设置'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('TS Phone 服务'), findsOneWidget);

    await tester.tap(find.text('TS Phone 服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary connection action exposes a busy state', (
    WidgetTester tester,
  ) async {
    final verification = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionPage(
          verifier: (_) => verification.future,
          onConnected: (_) async {},
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '访问令牌'),
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pump();

    expect(find.text('正在连接'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    verification.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive controls have visible pressed-state feedback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(TsPhoneApp(settingsStore: MemorySettingsStore()));
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(ConnectionPage)));
    final style = theme.iconButtonTheme.style!;

    expect(style.minimumSize!.resolve(<WidgetState>{}), const Size.square(48));
    expect(
      style.overlayColor!.resolve(<WidgetState>{WidgetState.pressed}),
      isNotNull,
    );
    expect(theme.splashColor.a, greaterThan(0));
  });

  testWidgets('switches the full app to English and restores the preference', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..value = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(store.localePreference, AppLocalePreference.en);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('TS Phone service'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('English connection UI fits a narrow phone screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..localePreference = AppLocalePreference.en;

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();

    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Access token'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in <AppLocalePreference>[
    AppLocalePreference.zh,
    AppLocalePreference.en,
  ]) {
    testWidgets('large text connection UI fits 320px for ${locale.name}', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = MemorySettingsStore()..localePreference = locale;

      await tester.pumpWidget(TsPhoneApp(settingsStore: store));
      await tester.pumpAndSettle();

      expect(find.byType(TsGlassAppBar), findsOneWidget);
      expect(find.byType(TsGlassSurface), findsOneWidget);
      expect(find.byType(TsPhoneBrandBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English settings UI fits a narrow phone screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..localePreference = AppLocalePreference.en
      ..value = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Chinese'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings use iOS grouped sections and segmented controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..value = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.byType(TsSettingsSection), findsNWidgets(4));
    expect(find.byType(TsGlassAppBar), findsOneWidget);
    expect(find.byType(TsGlassSurface), findsNWidgets(4));
    expect(find.byType(TsPhoneBrandBadge), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CupertinoSlidingSegmentedControl,
      ),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection diagnostics report verified server facts', (
    WidgetTester tester,
  ) async {
    final settings = ConnectionSettings(
      serverUrl: 'https://tsphone.iawnix.xyz',
      token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
    );
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], startsWith('Bearer '));
      return http.Response(
        '{"apiVersion":"ts-phone-api/3","data":{"apiVersion":"ts-phone-api/3","serviceVersion":"0.4.1"}}',
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
        home: SettingsPage(
          connectionSettings: settings,
          themePreference: AppThemePreference.system,
          localePreference: AppLocalePreference.en,
          onThemeChanged: (_) async {},
          onLocaleChanged: (_) async {},
          onEditConnection: () {},
          onClose: () {},
          gatewayBuilder: (settings) => TsPhoneApi(settings, client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Run connection diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('ts-phone-api/3'), findsOneWidget);
    expect(find.text('Ping'), findsNothing);
    expect(find.text('Runtime'), findsNothing);
    expect(find.text('Node ID'), findsNothing);
    expect(find.text('Server 0.4.1'), findsNothing);
    expect(find.text('Not exposed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in <AppLocalePreference>[
    AppLocalePreference.zh,
    AppLocalePreference.en,
  ]) {
    testWidgets('large text settings adapt on 320px for ${locale.name}', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = MemorySettingsStore()
        ..localePreference = locale
        ..value = ConnectionSettings(
          serverUrl: 'https://tsphone.iawnix.xyz',
          token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
        );

      await tester.pumpWidget(TsPhoneApp(settingsStore: store));
      await tester.pumpAndSettle();
      final settingsTooltip = locale == AppLocalePreference.zh
          ? '设置'
          : 'Settings';
      await tester.tap(find.byTooltip(settingsTooltip));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is CupertinoSlidingSegmentedControl,
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  for (final preference in <AppThemePreference>[
    AppThemePreference.light,
    AppThemePreference.dark,
  ]) {
    testWidgets('settings do not overflow in ${preference.name} mode', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemorySettingsStore()
        ..themePreference = preference
        ..localePreference = AppLocalePreference.en
        ..value = ConnectionSettings(
          serverUrl: 'https://tsphone.iawnix.xyz',
          token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
        );

      await tester.pumpWidget(TsPhoneApp(settingsStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('light and dark themes keep distinct neutral surfaces', () {
    final light = TsPhoneTheme.light().colorScheme;
    final dark = TsPhoneTheme.dark().colorScheme;
    final lightStatus = TsPhoneTheme.light().extension<TsPhoneStatusTheme>()!;
    final darkStatus = TsPhoneTheme.dark().extension<TsPhoneStatusTheme>()!;

    expect(light.surface, isNot(light.primaryContainer));
    expect(dark.surface, isNot(dark.primaryContainer));
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.primary, const Color(0xFF007AFF));
    expect(dark.surface, const Color(0xFF0B0F14));
    expect(lightStatus.connected, const Color(0xFF00A884));
    expect(darkStatus.connected, const Color(0xFF00C2A8));
    expect(darkStatus.warning, const Color(0xFFFFB020));
    expect(darkStatus.error, const Color(0xFFFF453A));
    expect(TsPhoneTheme.light().cardTheme.elevation, 0);
  });

  test('invalid stored theme values fall back to the system theme', () {
    expect(
      AppThemePreference.fromStorage('unsupported'),
      AppThemePreference.system,
    );
  });

  test('invalid stored locale values fall back to the system locale', () {
    expect(
      AppLocalePreference.fromStorage('unsupported'),
      AppLocalePreference.system,
    );
  });
}

class MemorySettingsStore implements SettingsStore {
  ConnectionSettings? value;
  AppThemePreference themePreference = AppThemePreference.system;
  AppLocalePreference localePreference = AppLocalePreference.zh;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<ConnectionSettings?> load() async => value;

  @override
  Future<AppThemePreference> loadThemePreference() async => themePreference;

  @override
  Future<AppLocalePreference> loadLocalePreference() async => localePreference;

  @override
  Future<void> save(ConnectionSettings settings) async => value = settings;

  @override
  Future<void> saveThemePreference(AppThemePreference preference) async {
    themePreference = preference;
  }

  @override
  Future<void> saveLocalePreference(AppLocalePreference preference) async {
    localePreference = preference;
  }
}
