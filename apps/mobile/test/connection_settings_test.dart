import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/models/connection_settings.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  test('normalizes HTTPS origins and builds API endpoints', () {
    final settings = ConnectionSettings(
      serverUrl: 'https://tsphone.iawnix.xyz/',
      token: token,
    );
    expect(settings.serverUrl, 'https://tsphone.iawnix.xyz');
    expect(
      settings.endpoint('workspaces').toString(),
      'https://tsphone.iawnix.xyz/api/v4/workspaces',
    );
  });

  test('allows plaintext only on loopback', () {
    expect(
      ConnectionSettings(
        serverUrl: 'http://127.0.0.1:22113',
        token: token,
      ).serverUrl,
      'http://127.0.0.1:22113',
    );
    expect(
      () => ConnectionSettings(
        serverUrl: 'http://192.168.1.2:22113',
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      ConnectionSettings(
        serverUrl: 'http://[::1]:22113',
        token: token,
      ).serverUrl,
      'http://[::1]:22113',
    );
  });

  test('rejects paths, embedded credentials, and short tokens', () {
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://example.test/proxy',
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://user@example.test',
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      () =>
          ConnectionSettings(serverUrl: 'https://example.test', token: 'short'),
      throwsFormatException,
    );
  });
}
