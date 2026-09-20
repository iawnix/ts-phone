import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ts_phone/data/tspi_link_pairing.dart';

const _hostId = '123e4567-e89b-42d3-a456-426614174000';
const _deviceId = '223e4567-e89b-42d3-a456-426614174000';
const _deviceToken = 'tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

void main() {
  test('redeems a normalized pairing code for device credentials', () async {
    late http.Request captured;
    final client = TspiLinkPairingClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'protocol': 'tspi-link.v1',
            'relayUrl': 'https://link.example.test',
            'hostId': _hostId,
            'deviceId': _deviceId,
            'deviceToken': _deviceToken,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final settings = await client.redeem(
      relayUrl: 'https://link.example.test/',
      pairingCode: 'abcd-efgh',
      deviceName: 'Lab Phone',
    );

    expect(captured.method, 'POST');
    expect(
      captured.url,
      Uri.parse('https://link.example.test/v1/pairings/redeem'),
    );
    expect(jsonDecode(captured.body), {
      'code': 'ABCDEFGH',
      'deviceName': 'Lab Phone',
    });
    expect(settings.serverUrl, 'https://link.example.test');
    expect(settings.serverId, _hostId);
    expect(settings.deviceId, _deviceId);
    expect(settings.token, _deviceToken);
  });

  test('preserves the Relay error code for localized presentation', () async {
    final client = TspiLinkPairingClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'invalid_pairing',
            'message': 'the pairing code is invalid or expired',
          }),
          400,
        ),
      ),
    );

    await expectLater(
      client.redeem(
        relayUrl: 'https://link.example.test',
        pairingCode: 'ABCDEFGH',
        deviceName: 'Lab Phone',
      ),
      throwsA(
        isA<TspiLinkPairingException>().having(
          (error) => error.code,
          'code',
          'invalid_pairing',
        ),
      ),
    );
  });

  test('rejects credentials issued for a different Relay origin', () async {
    final client = TspiLinkPairingClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'protocol': 'tspi-link.v1',
            'relayUrl': 'https://other.example.test',
            'hostId': _hostId,
            'deviceId': _deviceId,
            'deviceToken': _deviceToken,
          }),
          201,
        ),
      ),
    );

    await expectLater(
      client.redeem(
        relayUrl: 'https://link.example.test',
        pairingCode: 'ABCDEFGH',
        deviceName: 'Lab Phone',
      ),
      throwsA(
        isA<TspiLinkPairingException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('rejects an oversized Relay response', () async {
    final client = TspiLinkPairingClient(
      client: MockClient(
        (_) async => http.Response('x' * (64 * 1024 + 1), 200),
      ),
    );

    await expectLater(
      client.redeem(
        relayUrl: 'https://link.example.test',
        pairingCode: 'ABCDEFGH',
        deviceName: 'Lab Phone',
      ),
      throwsA(
        isA<TspiLinkPairingException>()
            .having((error) => error.code, 'code', 'invalid_response')
            .having((error) => error.message, 'message', contains('too large')),
      ),
    );
  });
}
