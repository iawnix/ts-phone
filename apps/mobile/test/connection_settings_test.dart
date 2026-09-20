import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/models/connection_settings.dart';

void main() {
  const hostId = '123e4567-e89b-42d3-a456-426614174000';
  const deviceId = '223e4567-e89b-42d3-a456-426614174000';
  const token = 'tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  test('normalizes HTTPS Relay origins', () {
    final settings = ConnectionSettings(
      serverUrl: 'https://tsphone.iawnix.xyz/',
      serverId: hostId,
      deviceId: deviceId,
      token: token,
    );
    expect(settings.serverUrl, 'https://tsphone.iawnix.xyz');
  });

  test('allows plaintext only on loopback', () {
    expect(
      ConnectionSettings(
        serverUrl: 'http://127.0.0.1:22113',
        serverId: hostId,
        deviceId: deviceId,
        token: token,
      ).serverUrl,
      'http://127.0.0.1:22113',
    );
    expect(
      () => ConnectionSettings(
        serverUrl: 'http://192.168.1.2:22113',
        serverId: hostId,
        deviceId: deviceId,
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      ConnectionSettings(
        serverUrl: 'http://[::1]:22113',
        serverId: hostId,
        deviceId: deviceId,
        token: token,
      ).serverUrl,
      'http://[::1]:22113',
    );
  });

  test('rejects paths, embedded credentials, and short tokens', () {
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://example.test/proxy',
        serverId: hostId,
        deviceId: deviceId,
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://user@example.test',
        serverId: hostId,
        deviceId: deviceId,
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://example.test',
        serverId: hostId,
        deviceId: deviceId,
        token: 'short',
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid Host and Device identities', () {
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://example.test',
        serverId: 'not-a-host',
        deviceId: deviceId,
        token: token,
      ),
      throwsFormatException,
    );
    expect(
      () => ConnectionSettings(
        serverUrl: 'https://example.test',
        serverId: hostId,
        deviceId: 'not-a-device',
        token: token,
      ),
      throwsFormatException,
    );
  });
}
