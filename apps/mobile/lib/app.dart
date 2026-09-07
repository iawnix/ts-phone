import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/settings_store.dart';
import 'features/connection/connection_page.dart';
import 'features/settings/settings_page.dart';
import 'features/sessions/conversation_shell.dart';
import 'l10n/app_localizations.dart';
import 'models/app_locale_preference.dart';
import 'models/app_theme_preference.dart';
import 'models/connection_settings.dart';
import 'navigation/adaptive_page_route.dart';
import 'platform/ts_accessibility_controller.dart';
import 'theme/ts_phone_theme.dart';
import 'theme/ts_visual_accessibility.dart';
import 'widgets/presentation.dart';

class TsPhoneApp extends StatefulWidget {
  const TsPhoneApp({
    super.key,
    required this.settingsStore,
    this.accessibilityController,
  });

  final SettingsStore settingsStore;
  final TsAccessibilityController? accessibilityController;

  @override
  State<TsPhoneApp> createState() => _TsPhoneAppState();
}

class _TsPhoneAppState extends State<TsPhoneApp> {
  late final TsAccessibilityController _visualAccessibility;
  late final bool _ownsVisualAccessibility;
  ConnectionSettings? _settings;
  AppThemePreference _themePreference = AppThemePreference.system;
  AppLocalePreference _localePreference = AppLocalePreference.system;
  bool _loading = true;
  bool _visualAccessibilityReady = false;
  bool _loadFailed = false;
  bool _retryLoadLatched = false;
  bool _settingsRouteOpen = false;
  bool _connectionEditorOpen = false;
  int _connectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ownsVisualAccessibility = widget.accessibilityController == null;
    _visualAccessibility =
        widget.accessibilityController ?? TsAccessibilityController();
    unawaited(_initializeVisualAccessibility());
    _load();
  }

  Future<void> _initializeVisualAccessibility() async {
    try {
      await _visualAccessibility.initialize();
      if (!mounted) return;
      setState(() => _visualAccessibilityReady = true);
    } on Object {
      // Keep the opaque fallback when the optional platform bridge is absent.
    }
  }

  @override
  void dispose() {
    if (_ownsVisualAccessibility) _visualAccessibility.dispose();
    super.dispose();
  }

  Future<void> _load({bool retry = false}) async {
    if (retry) {
      if (_loading || _retryLoadLatched) return;
      _retryLoadLatched = true;
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final settingsFuture = widget.settingsStore.load();
      final themeFuture = widget.settingsStore.loadThemePreference();
      final localeFuture = widget.settingsStore.loadLocalePreference();
      final results = await Future.wait<Object?>(<Future<Object?>>[
        settingsFuture,
        themeFuture,
        localeFuture,
      ]);
      final settings = results[0] as ConnectionSettings?;
      final themePreference = results[1] as AppThemePreference;
      final localePreference = results[2] as AppLocalePreference;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _themePreference = themePreference;
        _localePreference = localePreference;
        _loading = false;
        _loadFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    } finally {
      if (retry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _retryLoadLatched = false;
        });
      }
    }
  }

  Future<void> _save(ConnectionSettings settings) async {
    await widget.settingsStore.save(settings);
    if (!mounted) return;
    setState(() {
      if (_settings?.serverUrl != settings.serverUrl ||
          _settings?.token != settings.token) {
        _connectionGeneration += 1;
      }
      _settings = settings;
    });
  }

  Future<void> _saveTheme(AppThemePreference preference) async {
    await widget.settingsStore.saveThemePreference(preference);
    if (!mounted) return;
    setState(() => _themePreference = preference);
  }

  Future<void> _saveLocale(AppLocalePreference preference) async {
    await widget.settingsStore.saveLocalePreference(preference);
    if (!mounted) return;
    setState(() => _localePreference = preference);
  }

  Future<void> _openConnectionEditor(BuildContext context) async {
    if (_connectionEditorOpen) return;
    _connectionEditorOpen = true;
    try {
      await pushTsPhonePage<void>(
        context: context,
        builder: (routeContext) => ConnectionPage(
          initialSettings: _settings,
          onConnected: (settings) async {
            await _save(settings);
            if (routeContext.mounted) Navigator.of(routeContext).pop();
          },
          onBack: () => Navigator.of(routeContext).maybePop(),
        ),
      );
    } finally {
      _connectionEditorOpen = false;
    }
  }

  Future<void> _openSettings(BuildContext context) async {
    if (_settingsRouteOpen) return;
    _settingsRouteOpen = true;
    try {
      await pushTsPhonePage<void>(
        context: context,
        builder: (routeContext) => StatefulBuilder(
          builder: (context, refreshRoute) => SettingsPage(
            connectionSettings: _settings,
            themePreference: _themePreference,
            localePreference: _localePreference,
            onThemeChanged: (preference) async {
              await _saveTheme(preference);
              if (routeContext.mounted) refreshRoute(() {});
            },
            onLocaleChanged: (preference) async {
              await _saveLocale(preference);
              if (routeContext.mounted) refreshRoute(() {});
            },
            onEditConnection: () {
              unawaited(
                _openConnectionEditor(routeContext).whenComplete(() {
                  if (routeContext.mounted) refreshRoute(() {});
                }),
              );
            },
            onClose: () => Navigator.of(routeContext).maybePop(),
          ),
        ),
      );
    } finally {
      _settingsRouteOpen = false;
    }
  }

  Widget _home(BuildContext context) {
    if (_loading) return const _LoadingPage();
    if (_loadFailed) {
      return _SettingsLoadFailurePage(
        onRetry: () => unawaited(_load(retry: true)),
      );
    }
    final settings = _settings;
    if (settings == null) {
      return ConnectionPage(
        onConnected: _save,
        onOpenSettings: () => unawaited(_openSettings(context)),
      );
    }
    return ConversationShell(
      key: ValueKey(_connectionGeneration),
      settings: settings,
      onOpenSettings: () => unawaited(_openSettings(context)),
      selectionStore: widget.settingsStore is ConversationSelectionStore
          ? widget.settingsStore as ConversationSelectionStore
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: _localePreference.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: TsPhoneTheme.light(),
      darkTheme: TsPhoneTheme.dark(),
      highContrastTheme: TsPhoneTheme.highContrastLight(),
      highContrastDarkTheme: TsPhoneTheme.highContrastDark(),
      themeMode: switch (_themePreference) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      builder: (context, child) => ListenableBuilder(
        listenable: _visualAccessibility,
        builder: (context, _) => TsVisualAccessibility(
          reduceTransparency:
              !_visualAccessibilityReady ||
              _visualAccessibility.reduceTransparency,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            key: const ValueKey<String>('system-ui-overlay'),
            value: TsPhoneTheme.systemUiOverlayStyle(
              Theme.of(context).colorScheme,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      home: Builder(builder: _home),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _SettingsLoadFailurePage extends StatelessWidget {
  const _SettingsLoadFailurePage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey<String>('settings-load-error'),
      body: TsPageBackdrop(
        child: SafeArea(
          child: TsEmptyState(
            icon: Icons.settings_backup_restore_rounded,
            title: l10n.appTitle,
            message: l10n.settingsLoadFailed,
            action: FilledButton.icon(
              key: const ValueKey<String>('settings-load-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ),
        ),
      ),
    );
  }
}
