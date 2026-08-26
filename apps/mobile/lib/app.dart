import 'package:flutter/material.dart';

import 'data/settings_store.dart';
import 'features/connection/connection_page.dart';
import 'features/settings/settings_page.dart';
import 'features/workspaces/workspace_list_page.dart';
import 'l10n/app_localizations.dart';
import 'models/app_locale_preference.dart';
import 'models/app_theme_preference.dart';
import 'models/connection_settings.dart';
import 'theme/ts_phone_theme.dart';

class TsPhoneApp extends StatefulWidget {
  const TsPhoneApp({super.key, required this.settingsStore});

  final SettingsStore settingsStore;

  @override
  State<TsPhoneApp> createState() => _TsPhoneAppState();
}

class _TsPhoneAppState extends State<TsPhoneApp> {
  ConnectionSettings? _settings;
  AppThemePreference _themePreference = AppThemePreference.system;
  AppLocalePreference _localePreference = AppLocalePreference.system;
  bool _loading = true;
  bool _showSettings = false;
  bool _editingConnection = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    });
  }

  Future<void> _save(ConnectionSettings settings) async {
    await widget.settingsStore.save(settings);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _editingConnection = false;
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
      themeMode: switch (_themePreference) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      home: _loading
          ? const _LoadingPage()
          : _editingConnection || (_settings == null && !_showSettings)
          ? ConnectionPage(
              initialSettings: _settings,
              onConnected: _save,
              onBack: _editingConnection
                  ? () => setState(() => _editingConnection = false)
                  : null,
              onOpenSettings: _editingConnection
                  ? null
                  : () => setState(() => _showSettings = true),
            )
          : _showSettings
          ? SettingsPage(
              connectionSettings: _settings,
              themePreference: _themePreference,
              localePreference: _localePreference,
              onThemeChanged: _saveTheme,
              onLocaleChanged: _saveLocale,
              onEditConnection: () => setState(() => _editingConnection = true),
              onClose: () => setState(() => _showSettings = false),
            )
          : WorkspaceListPage(
              settings: _settings!,
              onOpenSettings: () => setState(() => _showSettings = true),
            ),
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
