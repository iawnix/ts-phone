import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/app.dart';
import 'package:ts_phone/data/settings_store.dart';
import 'package:ts_phone/data/ts_phone_api.dart';
import 'package:ts_phone/features/connection/connection_page.dart';
import 'package:ts_phone/features/settings/settings_page.dart';
import 'package:ts_phone/features/sessions/session_list_page.dart';
import 'package:ts_phone/features/workspaces/workspace_list_page.dart';
import 'package:ts_phone/l10n/app_localizations.dart';
import 'package:ts_phone/models/app_locale_preference.dart';
import 'package:ts_phone/models/app_theme_preference.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/workspace.dart';
import 'package:ts_phone/navigation/adaptive_page_route.dart';
import 'package:ts_phone/platform/ts_accessibility_controller.dart';
import 'package:ts_phone/theme/ts_visual_accessibility.dart';
import 'package:ts_phone/widgets/presentation.dart';

final _settings = ConnectionSettings(
  serverUrl: 'https://tsphone.example.test',
  token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
);

const _workspace = WorkspaceSummary(
  id: 'ts_001',
  name: 'TS study',
  runtimeState: RuntimeState.idle,
  isStreaming: false,
  liveSessionCount: 1,
  sessionCount: 1,
);

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets('adaptive page route follows the $platform convention', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey<String>('open-route'),
              onPressed: () => pushTsPhonePage<void>(
                context: context,
                builder: (context) => const Scaffold(
                  body: Text('Destination', key: ValueKey('destination')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('open-route')));
      await tester.pumpAndSettle();

      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey<String>('destination'))),
      );
      if (platform == TargetPlatform.iOS) {
        expect(route, isA<CupertinoPageRoute<void>>());
      } else {
        expect(route, isA<MaterialPageRoute<void>>());
      }
    });
  }

  testWidgets('initial settings failure can be retried', (tester) async {
    final store = _TestSettingsStore(failFirstLoad: true);

    await tester.pumpWidget(TsPhoneApp(settingsStore: store));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-load-error')),
      findsOneWidget,
    );
    expect(find.byType(ConnectionPage), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('settings-load-retry')));
    await tester.tap(find.byKey(const ValueKey<String>('settings-load-retry')));
    await tester.pumpAndSettle();

    expect(store.connectionLoadCalls, 2);
    expect(find.byType(ConnectionPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-load-error')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform accessibility probe never blocks app startup', (
    tester,
  ) async {
    final probe = Completer<bool>();
    final accessibility = TsAccessibilityController(
      probe: () => probe.future,
      changes: const Stream<bool>.empty(),
    );
    addTearDown(accessibility.dispose);

    await tester.pumpWidget(
      TsPhoneApp(
        settingsStore: _TestSettingsStore(),
        accessibilityController: accessibility,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ConnectionPage), findsOneWidget);
    expect(
      tester
          .widget<TsVisualAccessibility>(find.byType(TsVisualAccessibility))
          .reduceTransparency,
      isTrue,
    );

    probe.complete(false);
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<TsVisualAccessibility>(find.byType(TsVisualAccessibility))
          .reduceTransparency,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated settings taps open only one route', (tester) async {
    await tester.pumpWidget(TsPhoneApp(settingsStore: _TestSettingsStore()));
    await tester.pumpAndSettle();

    final settingsButton = find.byKey(
      const ValueKey<String>('connection-settings'),
    );
    final openSettings = tester.widget<IconButton>(settingsButton).onPressed!;
    openSettings();
    openSettings();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(ConnectionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace opening is visible and mutually exclusive', (
    tester,
  ) async {
    final gateway = _PendingSessionGateway();
    var settingsOpenCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () => settingsOpenCalls += 1,
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey<String>('workspace-row-ts_001'));
    await tester.tap(row);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('workspace-opening-ts_001')),
      findsOneWidget,
    );
    expect(gateway.listSessionsCalls, 1);

    await tester.tap(row);
    await tester.tap(find.byKey(const ValueKey<String>('workspace-settings')));
    await tester.pump();
    expect(gateway.listSessionsCalls, 1);
    expect(settingsOpenCalls, 0);

    gateway.sessions.completeError(Exception('session lookup failed'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('workspace-opening-ts_001')),
      findsNothing,
    );
    expect(gateway.listSessionsCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace rows stay readable on a wide viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _PendingSessionGateway();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: WorkspaceListPage(
          settings: _settings,
          onOpenSettings: () {},
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey<String>('workspace-row-ts_001'));
    final rect = tester.getRect(row);
    expect(rect.width, lessThanOrEqualTo(800));
    expect(rect.center.dx, closeTo(512, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated session taps push only one chat route', (tester) async {
    final observer = _RouteCountingObserver();
    final gateway = _PendingSessionGateway();
    const session = SessionSummary(
      sessionId: 'session-1',
      sessionRevision: '11111111-1111-4111-8111-111111111111',
      sessionName: 'Main session',
      runtimeState: RuntimeState.idle,
      isStreaming: false,
      accessMode: SessionAccessMode.controller,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SessionListPage(
          settings: _settings,
          workspace: _workspace,
          initialSessions: const <SessionSummary>[session],
          gatewayBuilder: (_) => gateway,
        ),
      ),
    );
    await tester.pump();

    final tile = tester.widget<TsStatusListTile>(find.byType(TsStatusListTile));
    tile.onTap!();
    tile.onTap!();

    expect(observer.pushCount, 2); // Initial route plus one chat route.
    expect(tester.takeException(), isNull);
  });
}

class _RouteCountingObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount += 1;
    super.didPush(route, previousRoute);
  }
}

class _TestSettingsStore implements SettingsStore {
  _TestSettingsStore({this.failFirstLoad = false});

  final bool failFirstLoad;
  int connectionLoadCalls = 0;

  @override
  Future<void> clear() async {}

  @override
  Future<ConnectionSettings?> load() async {
    connectionLoadCalls += 1;
    if (failFirstLoad && connectionLoadCalls == 1) {
      throw Exception('secure storage unavailable');
    }
    return null;
  }

  @override
  Future<AppLocalePreference> loadLocalePreference() async =>
      AppLocalePreference.en;

  @override
  Future<AppThemePreference> loadThemePreference() async =>
      AppThemePreference.system;

  @override
  Future<void> save(ConnectionSettings settings) async {}

  @override
  Future<void> saveLocalePreference(AppLocalePreference preference) async {}

  @override
  Future<void> saveThemePreference(AppThemePreference preference) async {}
}

class _PendingSessionGateway implements TsPhoneGateway {
  final Completer<List<SessionSummary>> sessions =
      Completer<List<SessionSummary>>();
  int listSessionsCalls = 0;

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) => throw UnimplementedError();

  @override
  void close() {}

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) => const Stream<TsPhoneEvent>.empty();

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) => throw UnimplementedError();

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) => throw UnimplementedError();

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) {
    listSessionsCalls += 1;
    return sessions.future;
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      const <WorkspaceSummary>[_workspace];

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) => throw UnimplementedError();

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, Object?>> version() => throw UnimplementedError();
}
