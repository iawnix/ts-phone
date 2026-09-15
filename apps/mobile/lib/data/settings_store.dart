import 'dart:convert';

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

abstract interface class ConversationSelectionStore {
  Future<(String, String)?> loadConversation(String endpoint);
  Future<void> saveConversation(
    String endpoint,
    String workspace,
    String session,
  );
}

class SecureSettingsStore implements SettingsStore, ConversationSelectionStore {
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
  static const _serverIdKey = 'app_server_id';
  static const _tokenKey = 'auth_token';
  static const _themeKey = 'theme_mode';
  static const _localeKey = 'locale_mode';
  static const _conversationKey = 'last_conversation';
  final FlutterSecureStorage _storage;

  @override
  Future<ConnectionSettings?> load() async {
    final values = await Future.wait(<Future<String?>>[
      _storage.read(key: _serverKey),
      _storage.read(key: _serverIdKey),
      _storage.read(key: _tokenKey),
    ]);
    if (values[0] == null || values[1] == null || values[2] == null) {
      return null;
    }
    try {
      return ConnectionSettings(
        serverUrl: values[0]!,
        serverId: values[1]!,
        token: values[2]!,
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(ConnectionSettings settings) async {
    final previous = await load();
    if (previous?.serverUrl != settings.serverUrl ||
        previous?.serverId != settings.serverId ||
        previous?.token != settings.token) {
      await _storage.delete(key: _conversationKey);
    }
    await _storage.write(key: _serverKey, value: settings.serverUrl);
    await _storage.write(key: _serverIdKey, value: settings.serverId);
    await _storage.write(key: _tokenKey, value: settings.token);
  }

  @override
  Future<(String, String)?> loadConversation(String endpoint) async {
    final raw = await _storage.read(key: _conversationKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is Map &&
          value['endpoint'] == endpoint &&
          value['workspace'] is String &&
          value['session'] is String) {
        return (value['workspace'] as String, value['session'] as String);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  Future<void> saveConversation(
    String endpoint,
    String workspace,
    String session,
  ) => _storage.write(
    key: _conversationKey,
    value: jsonEncode({
      'endpoint': endpoint,
      'workspace': workspace,
      'session': session,
    }),
  );

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
      _storage.delete(key: _serverIdKey),
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _conversationKey),
    ]);
  }
}
