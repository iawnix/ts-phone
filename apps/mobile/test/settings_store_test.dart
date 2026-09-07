import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/settings_store.dart';
import 'package:ts_phone/models/app_theme_preference.dart';
import 'package:ts_phone/models/app_locale_preference.dart';
import 'package:ts_phone/models/connection_settings.dart';

void main() {
  test(
    'last conversation is endpoint scoped and cleared on credential change',
    () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final store = SecureSettingsStore(storage: const FlutterSecureStorage());
      final connection = ConnectionSettings(
        serverUrl: 'https://phone.test',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );
      await store.save(connection);
      await store.saveConversation(connection.serverUrl, 'ts_001', 'session_2');
      expect(await store.loadConversation(connection.serverUrl), (
        'ts_001',
        'session_2',
      ));
      expect(await store.loadConversation('https://another.test'), isNull);
      await store.save(connection);
      expect(await store.loadConversation(connection.serverUrl), (
        'ts_001',
        'session_2',
      ));
      await store.save(
        ConnectionSettings(
          serverUrl: connection.serverUrl,
          token: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq',
        ),
      );
      expect(await store.loadConversation(connection.serverUrl), isNull);
    },
  );

  test(
    'clearing connection credentials preserves the theme preference',
    () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      const storage = FlutterSecureStorage();
      final store = SecureSettingsStore(storage: storage);
      final connection = ConnectionSettings(
        serverUrl: 'https://tsphone.iawnix.xyz',
        token: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
      );

      await store.save(connection);
      await store.saveThemePreference(AppThemePreference.dark);
      await store.saveLocalePreference(AppLocalePreference.en);
      await store.clear();

      expect(await store.load(), isNull);
      expect(await store.loadThemePreference(), AppThemePreference.dark);
      expect(await store.loadLocalePreference(), AppLocalePreference.en);
    },
  );
}
