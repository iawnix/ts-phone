import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_theme_preference.dart';
import '../models/app_locale_preference.dart';
import '../models/connection_settings.dart';

abstract interface class SettingsStore {
  Future<ConnectionSettings?> load();
  Future<void> save(ConnectionSettings settings);
  Future<AppThemePreference> loadThemePreference();
  Future<void> saveThemePreference(AppThemePreference preference);
  Future<AppLocalePreference> loadLocalePreference();
  Future<void> saveLocalePreference(AppLocalePreference preference);
  Future<void> clear();
}

class SecureSettingsStore implements SettingsStore {
  SecureSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'ts_phone'),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const _serverKey = 'server_url';
  static const _tokenKey = 'auth_token';
  static const _themeKey = 'theme_mode';
  static const _localeKey = 'locale_mode';
  final FlutterSecureStorage _storage;

  @override
  Future<ConnectionSettings?> load() async {
    final values = await Future.wait(<Future<String?>>[
      _storage.read(key: _serverKey),
      _storage.read(key: _tokenKey),
    ]);
    if (values[0] == null || values[1] == null) return null;
    try {
      return ConnectionSettings(serverUrl: values[0]!, token: values[1]!);
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(ConnectionSettings settings) async {
    await _storage.write(key: _serverKey, value: settings.serverUrl);
    await _storage.write(key: _tokenKey, value: settings.token);
  }

  @override
  Future<AppThemePreference> loadThemePreference() async {
    return AppThemePreference.fromStorage(await _storage.read(key: _themeKey));
  }

  @override
  Future<void> saveThemePreference(AppThemePreference preference) {
    return _storage.write(key: _themeKey, value: preference.name);
  }

  @override
  Future<AppLocalePreference> loadLocalePreference() async {
    return AppLocalePreference.fromStorage(
      await _storage.read(key: _localeKey),
    );
  }

  @override
  Future<void> saveLocalePreference(AppLocalePreference preference) {
    return _storage.write(key: _localeKey, value: preference.name);
  }

  @override
  Future<void> clear() async {
    await Future.wait(<Future<void>>[
      _storage.delete(key: _serverKey),
      _storage.delete(key: _tokenKey),
    ]);
  }
}
