import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/connection_settings.dart';

typedef LinkPairingRedeemer =
    Future<ConnectionSettings> Function({
      required String relayUrl,
      required String pairingCode,
      required String deviceName,
    });

const _maxPairingResponseBytes = 64 * 1024;
const _pairingTimeout = Duration(seconds: 20);

class LinkPairingException implements Exception {
  const LinkPairingException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class LinkPairingClient {
  LinkPairingClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<ConnectionSettings> redeem({
    required String relayUrl,
    required String pairingCode,
    required String deviceName,
  }) async {
    final origin = ConnectionSettings.normalizeServerUrl(relayUrl);
    final code = pairingCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final name = deviceName.trim();
    if (code.length != 8) {
      throw const LinkPairingException(
        'invalid_pairing_code',
        'Pairing code must contain eight characters',
      );
    }
    if (name.isEmpty || name.length > 80 || name.codeUnits.any((v) => v < 32)) {
      throw const LinkPairingException(
        'invalid_device_name',
        'Device name is invalid',
      );
    }
    late http.StreamedResponse response;
    late String responseBody;
    try {
      final request =
          http.Request(
              'POST',
              Uri.parse(origin).replace(path: '/v1/pairings/redeem'),
            )
            ..headers.addAll(const <String, String>{
              'accept': 'application/json',
              'content-type': 'application/json',
            })
            ..body = jsonEncode(<String, Object?>{
              'code': code,
              'deviceName': name,
            });
      response = await _client.send(request).timeout(_pairingTimeout);
      responseBody = await _readBoundedBody(response).timeout(_pairingTimeout);
    } on LinkPairingException {
      rethrow;
    } on Object catch (error) {
      throw LinkPairingException(
        'relay_unavailable',
        'Could not reach CoRAgent Relay: $error',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException {
      throw const LinkPairingException(
        'invalid_response',
        'CoRAgent Relay returned an invalid response',
      );
    }
    if (decoded is! Map) {
      throw const LinkPairingException(
        'invalid_response',
        'CoRAgent Relay returned an invalid response',
      );
    }
    final value = decoded.cast<Object?, Object?>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = value['message'];
      throw LinkPairingException(
        value['error'] is String
            ? value['error']! as String
            : 'pairing_rejected',
        message is String ? message : 'CoRAgent Relay rejected pairing',
      );
    }
    if (value['protocol'] != 'research-agent-link.v1') {
      throw const LinkPairingException(
        'unsupported_protocol',
        'CoRAgent Relay uses an unsupported Link protocol',
      );
    }
    final returnedRelay = value['relayUrl'];
    final hostId = value['hostId'];
    final deviceId = value['deviceId'];
    final deviceToken = value['deviceToken'];
    if (returnedRelay is! String ||
        hostId is! String ||
        deviceId is! String ||
        deviceToken is! String) {
      throw const LinkPairingException(
        'invalid_response',
        'CoRAgent Relay returned incomplete credentials',
      );
    }
    final settings = ConnectionSettings(
      serverUrl: returnedRelay,
      serverId: hostId,
      deviceId: deviceId,
      token: deviceToken,
    );
    if (settings.serverUrl != origin) {
      throw const LinkPairingException(
        'invalid_response',
        'CoRAgent Relay returned a different Relay origin',
      );
    }
    return settings;
  }

  Future<String> _readBoundedBody(http.StreamedResponse response) async {
    if ((response.contentLength ?? 0) > _maxPairingResponseBytes) {
      throw const LinkPairingException(
        'invalid_response',
        'CoRAgent Relay response is too large',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxPairingResponseBytes) {
        throw const LinkPairingException(
          'invalid_response',
          'CoRAgent Relay response is too large',
        );
      }
      bytes.add(chunk);
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const LinkPairingException(
        'invalid_response',
        'CoRAgent Relay returned an invalid response',
      );
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
