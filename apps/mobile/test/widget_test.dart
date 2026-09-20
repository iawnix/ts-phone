import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/app.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/data/settings_store.dart';
import 'package:ts_phone/features/chat/timeline_widgets.dart';
import 'package:ts_phone/features/chat/chat_controller.dart';
import 'package:ts_phone/features/chat/live_run_strip.dart';
import 'package:ts_phone/features/connection/connection_page.dart';
import 'package:ts_phone/features/settings/settings_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/app_theme_preference.dart';
import 'package:ts_phone/models/app_locale_preference.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/session_timeline.dart';
import 'package:ts_phone/platform/ts_accessibility_controller.dart';
import 'package:ts_phone/theme/ts_phone_theme.dart';
import 'package:ts_phone/models/chat_message.dart';
import 'package:ts_phone/widgets/chat_message_view.dart';
import 'package:ts_phone/widgets/markdown_message.dart';
import 'package:ts_phone/widgets/presentation.dart';
import 'package:ts_phone/widgets/ts_phone_brand_mark.dart';

const _hostId = '123e4567-e89b-42d3-a456-426614174000';
const _deviceId = '223e4567-e89b-42d3-a456-426614174000';
const _deviceToken = 'tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

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

    expect(find.text('TS Phone'), findsWidgets);
    expect(find.text('TSPi Relay'), findsOneWidget);
    expect(find.text('配对码'), findsOneWidget);
    expect(find.text('设备名称'), findsOneWidget);
    expect(find.text('配对'), findsOneWidget);
    expect(find.byType(TsPhoneBrandMark), findsOneWidget);
    final connectButton = tester.getRect(
      find.byKey(const ValueKey<String>('connect-action')),
    );
    expect(connectButton.width, lessThanOrEqualTo(240));
    expect(connectButton.center.dx, closeTo(180, 0.5));
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

  for (final locale in const <Locale>[Locale('en'), Locale('zh')]) {
    testWidgets(
      'timeline filter uses a large-text menu in ${locale.languageCode}',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var selected = TimelineViewFilter.all;
        final activityLabel = locale.languageCode == 'zh' ? '活动' : 'Activity';

        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: TsPhoneTheme.light(),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: TimelineFilterControl(
                  selected: selected,
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('timeline-view-filter-menu')),
          findsOneWidget,
        );
        expect(
          find.byType(TsSegmentedControl<TimelineViewFilter>),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('timeline-view-filter-menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(activityLabel).last);
        await tester.pumpAndSettle();

        expect(selected, TimelineViewFilter.activities);
        expect(find.text(activityLabel), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('bounds long activity labels and reveals the exact tool name', (
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ChatMessageView(
              message: ChatMessage(
                role: ChatRole.assistant,
                text: '',
                tools: <ToolDetail>[
                  ToolDetail(
                    title: toolName,
                    body:
                        '{"valid": true, "artifact": "outputs/remote/a-very-long-calculation-artifact-name.json"}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(toolName.replaceAll('_', ' ')));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.text('就绪'), findsNothing);
    expect(find.text('TSPi'), findsNothing);
    expect(find.byKey(const ValueKey<String>('tool-raw-output')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('tool-disclosure-row')))
          .width,
      greaterThan(240),
    );

    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tool-raw-output')),
      findsOneWidget,
    );
    expect(find.textContaining(toolName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveals terminal styling only for expanded raw tool output', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ChatMessageView(
            message: ChatMessage(
              role: ChatRole.tool,
              text: '',
              tools: <ToolDetail>[
                ToolDetail(title: 'ts_calc', body: 'raw calculation output'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final disclosure = tester.widget<Material>(
      find.byKey(const ValueKey<String>('tool-disclosure-row')),
    );
    expect(disclosure.color, Colors.transparent);
    expect(find.text('TSPi'), findsNothing);
    expect(find.text('raw calculation output'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tool-disclosure-row')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tool-raw-output')),
      findsOneWidget,
    );
    expect(find.textContaining('raw calculation output'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrative has no repeated logo and preserves tool disclosure', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: const Scaffold(
          body: ChatMessageView(
            message: ChatMessage(
              role: ChatRole.assistant,
              text: 'Research result',
              tools: <ToolDetail>[ToolDetail(title: 'ts_change', body: '{}')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TSPi'), findsNothing);
    expect(find.text('Research result'), findsOneWidget);
    expect(find.text('记录研究决策'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tool-disclosure-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool-raw-output')), findsOneWidget);
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
        serverId: _hostId,
        deviceId: _deviceId,
        token: _deviceToken,
      );

    await tester.pumpWidget(_appWithStore(store));
    await tester.pumpAndSettle();
    await _openSettings(tester, '设置');
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('https://tsphone.iawnix.xyz'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('appearance-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(store.themePreference, AppThemePreference.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    final darkOverlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey<String>('system-ui-overlay')),
    );
    expect(darkOverlay.value.statusBarIconBrightness, Brightness.light);
    expect(
      darkOverlay.value.systemNavigationBarIconBrightness,
      Brightness.light,
    );
    expect(darkOverlay.value.systemNavigationBarColor, Colors.transparent);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_appWithStore(store));
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
        serverId: _hostId,
        deviceId: _deviceId,
        token: _deviceToken,
      );

    await tester.pumpWidget(_appWithStore(store));
    await tester.pumpAndSettle();
    await _openSettings(tester, '设置');
    await tester.pumpAndSettle();
    await tester.tap(find.text('TSPi Link').first);
    await tester.pumpAndSettle();

    expect(find.text('连接设置'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('TSPi Link'), findsWidgets);

    await tester.tap(find.text('TSPi Link').first);
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
          pairingRedeemer: _redeemTestPairing,
          verifier: (_) => verification.future,
          onConnected: (_) async {},
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('relay-url-field')),
      'https://link.example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('pairing-code-field')),
      'ABCD-EFGH',
    );
    await tester.tap(find.widgetWithText(FilledButton, '配对'));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('connecting')), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    verification.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discarded connection verification cannot save settings', (
    WidgetTester tester,
  ) async {
    final verification = Completer<void>();
    var savedConnections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionPage(
          pairingRedeemer: _redeemTestPairing,
          verifier: (_) => verification.future,
          onConnected: (_) async => savedConnections += 1,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('relay-url-field')),
      'https://link.example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('pairing-code-field')),
      'ABCD-EFGH',
    );
    await tester.tap(find.widgetWithText(FilledButton, '配对'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    verification.complete();
    await tester.pump();

    expect(savedConnections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection save cannot be dismissed midway', (
    WidgetTester tester,
  ) async {
    final save = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey<String>('open-connection-editor'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (routeContext) => ConnectionPage(
                  pairingRedeemer: _redeemTestPairing,
                  verifier: (_) async {},
                  onConnected: (_) => save.future,
                  onBack: () => Navigator.of(routeContext).maybePop(),
                ),
              ),
            ),
            child: const Text('Open connection editor'),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('open-connection-editor')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('relay-url-field')),
      'https://link.example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('pairing-code-field')),
      'ABCD-EFGH',
    );
    await tester.tap(find.widgetWithText(FilledButton, '配对'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ConnectionPage), findsOneWidget);

    save.complete();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionPage), findsNothing);
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
    expect(theme.splashFactory, same(NoSplash.splashFactory));
    expect(theme.highlightColor.a, greaterThan(0));
  });

  testWidgets('pulsing status indicators respect Reduce Motion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: Center(
              child: TsStatusDot(color: Colors.green, pulsing: true),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TsStatusDot), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass surfaces become opaque in high contrast mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TsPhoneTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: Scaffold(
            appBar: const TsGlassAppBar(title: Text('High contrast')),
            body: Center(
              child: TsGlassSurface(
                blurSigma: 24,
                child: SizedBox.square(dimension: 44),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TsGlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live glass status preserves a long tool name at large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: LiveRunStrip(
            activity: const ChatActivity(
              ChatActivityKind.runningTool,
              toolName: 'ts_workspace_decision_draft',
            ),
          ),
        ),
      ),
    );

    final label = find.textContaining('ts workspace decision draft');
    expect(label, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isTrue,
    );
    expect(find.byKey(const ValueKey<String>('live-run-stop')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed activity keeps its summary without duplicating stop', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.light(),
        home: Scaffold(
          body: LiveRunStrip(
            activity: const ChatActivity(
              ChatActivityKind.toolFailed,
              toolName: 'ts_calc',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tool failed: Calculation'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('live-run-stop')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed activity rail fits dark mode with 2x text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: TsPhoneTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: TimelineActivityView(
            identity: 'activity-failed',
            activity: TimelineActivity(
              category: TimelineActivityCategory.review,
              status: TimelineActivityStatus.failed,
              title: 'review_run',
              role: 'review',
              operation: 'validate',
              durationMs: 2400,
              detail: 'Result contract validation failed.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review · Validate'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('2.4s'), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
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
        serverId: _hostId,
        deviceId: _deviceId,
        token: _deviceToken,
      );

    await tester.pumpWidget(_appWithStore(store));
    await tester.pumpAndSettle();
    await _openSettings(tester, '设置');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(store.localePreference, AppLocalePreference.en);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('TSPi Link'), findsWidgets);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_appWithStore(store));
    await tester.pumpAndSettle();
    await _openSettings(tester, 'Settings');
    expect(find.text('Language'), findsOneWidget);
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

    await tester.pumpWidget(_appWithStore(store));
    await tester.pumpAndSettle();

    expect(find.text('TSPi Relay'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget);
    expect(find.text('Device name'), findsOneWidget);
    expect(find.text('Pair'), findsOneWidget);
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
      final accessibility = _glassAccessibilityController();
      addTearDown(accessibility.dispose);

      await tester.pumpWidget(
        _appWithStore(store, accessibilityController: accessibility),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TsGlassAppBar), findsOneWidget);
      expect(find.byType(TsContentSurface), findsOneWidget);
      expect(find.byType(TsGlassSurface), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TsGlassAppBar),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
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
        serverId: _hostId,
        deviceId: _deviceId,
        token: _deviceToken,
      );

    await tester.pumpWidget(_appWithStore(store));
    await tester.pumpAndSettle();
    await _openSettings(tester, 'Settings');
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-setting')));
    await tester.pumpAndSettle();
    expect(find.text('Chinese'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings use grouped rows and full-label choice sheets', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySettingsStore()
      ..value = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        serverId: _hostId,
        deviceId: _deviceId,
        token: _deviceToken,
      );
    final accessibility = _glassAccessibilityController();
    addTearDown(accessibility.dispose);

    await tester.pumpWidget(
      _appWithStore(store, accessibilityController: accessibility),
    );
    await tester.pumpAndSettle();
    await _openSettings(tester, '设置');
    await tester.pumpAndSettle();

    expect(find.byType(TsSettingsSection), findsNWidgets(3));
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(TsContentSurface), findsNothing);
    expect(find.byType(TsGlassSurface), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(find.byType(TsPhoneBrandBadge), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is TsSegmentedControl),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('appearance-setting')));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    for (final label in <String>[
      l10n.themeSystem,
      l10n.themeLight,
      l10n.themeDark,
    ]) {
      final text =
          tester.widget<ListTile>(find.widgetWithText(ListTile, label)).title!
              as Text;
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings wrap the endpoint and use a full-width diagnostics row',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = ConnectionSettings(
        serverUrl: 'https://link.example.test',
        serverId: _hostId,
        deviceId: _deviceId,
        token: _deviceToken,
      );

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
          ),
        ),
      );
      await tester.pumpAndSettle();

      final endpoint = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == settings.serverUrl,
      );
      expect(endpoint, findsNothing);
      final detailsToggle = find.byKey(
        const ValueKey<String>('connection-details-toggle'),
      );
      await tester.ensureVisible(detailsToggle);
      await tester.tap(detailsToggle);
      await tester.pumpAndSettle();

      expect(endpoint, findsOneWidget);
      await tester.ensureVisible(endpoint);
      await tester.pumpAndSettle();
      expect(tester.getSize(endpoint).height, greaterThan(20));
      final diagnosticsRow = tester.getRect(
        find.byKey(const ValueKey<String>('run-connection-diagnostics')),
      );
      expect(diagnosticsRow.width, greaterThan(260));
      expect(diagnosticsRow.center.dx, closeTo(160, 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connection diagnostics expose the Pi App Server protocol', (
    WidgetTester tester,
  ) async {
    final settings = ConnectionSettings(
      serverUrl: 'https://link.example.test',
      serverId: _hostId,
      deviceId: _deviceId,
      token: _deviceToken,
    );
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
          gatewayBuilder: (_) => _WidgetDiagnosticGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('run-connection-diagnostics')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Healthy'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('connection-details-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('pi-app-server/8'), findsOneWidget);
    expect(find.text('Pi App Server').last, findsOneWidget);
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
          serverId: _hostId,
          deviceId: _deviceId,
          token: _deviceToken,
        );

      await tester.pumpWidget(_appWithStore(store));
      await tester.pumpAndSettle();
      final settingsTooltip = locale == AppLocalePreference.zh
          ? '设置'
          : 'Settings';
      await _openSettings(tester, settingsTooltip);
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((widget) => widget is TsSegmentedControl),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('appearance-setting')), findsOneWidget);
      expect(find.byKey(const ValueKey('language-setting')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('appearance-setting')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
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
          serverId: _hostId,
          deviceId: _deviceId,
          token: _deviceToken,
        );

      await tester.pumpWidget(_appWithStore(store));
      await tester.pumpAndSettle();
      await _openSettings(tester, 'Settings');
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('light and dark themes keep distinct neutral surfaces', () {
    final lightTheme = TsPhoneTheme.light();
    final darkTheme = TsPhoneTheme.dark();
    final light = lightTheme.colorScheme;
    final dark = darkTheme.colorScheme;
    final lightStatus = lightTheme.extension<TsPhoneStatusTheme>()!;
    final darkStatus = darkTheme.extension<TsPhoneStatusTheme>()!;

    expect(light.surface, isNot(light.primaryContainer));
    expect(dark.surface, isNot(dark.primaryContainer));
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.primary, const Color(0xFF0068D0));
    expect(dark.surface, const Color(0xFF101010));
    expect(lightStatus.connected, const Color(0xFF007A5E));
    expect(darkStatus.connected, const Color(0xFF63E6BE));
    expect(darkStatus.warning, const Color(0xFFFFD166));
    expect(darkStatus.error, const Color(0xFFFF6961));
    expect(lightTheme.cardTheme.elevation, 0);
  });

  test('system chrome uses readable icons and theme-matched surfaces', () {
    final lightTheme = TsPhoneTheme.light();
    final darkTheme = TsPhoneTheme.dark();
    final light = TsPhoneTheme.systemUiOverlayStyle(lightTheme.colorScheme);
    final dark = TsPhoneTheme.systemUiOverlayStyle(darkTheme.colorScheme);

    expect(light.statusBarColor, Colors.transparent);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(light.statusBarBrightness, Brightness.light);
    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(light.systemStatusBarContrastEnforced, isTrue);
    expect(light.systemNavigationBarContrastEnforced, isFalse);
    expect(lightTheme.appBarTheme.systemOverlayStyle, light);

    expect(dark.statusBarColor, Colors.transparent);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(dark.statusBarBrightness, Brightness.dark);
    expect(dark.systemNavigationBarColor, Colors.transparent);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    expect(dark.systemStatusBarContrastEnforced, isTrue);
    expect(dark.systemNavigationBarContrastEnforced, isFalse);
    expect(darkTheme.appBarTheme.systemOverlayStyle, dark);
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

class _WidgetDiagnosticGateway implements TsPhoneGateway {
  @override
  Future<Map<String, Object?>> version() async => const {
    'apiVersion': 'pi-app-server/8',
    'serviceVersion': 'Pi App Server',
  };

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in widget diagnostics');
}

Widget _appWithStore(
  SettingsStore store, {
  TsAccessibilityController? accessibilityController,
}) => TsPhoneApp(
  settingsStore: store,
  accessibilityController: accessibilityController,
  gatewayBuilder: (_) => _WidgetDiagnosticGateway(),
  pairingRedeemer: _redeemTestPairing,
);

Future<ConnectionSettings> _redeemTestPairing({
  required String relayUrl,
  required String pairingCode,
  required String deviceName,
}) async => ConnectionSettings(
  serverUrl: relayUrl,
  serverId: _hostId,
  deviceId: _deviceId,
  token: _deviceToken,
);

Future<void> _openSettings(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(label));
  await tester.pumpAndSettle();
}

TsAccessibilityController _glassAccessibilityController() {
  return TsAccessibilityController(
    probe: () async => false,
    changes: const Stream<bool>.empty(),
  );
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
