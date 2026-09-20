enum ConnectionValidationReason {
  incompleteServerAddress,
  disallowedUrlComponents,
  originOnly,
  httpsRequired,
  invalidServerId,
  invalidDeviceId,
  invalidToken,
}

class ConnectionValidationException extends FormatException {
  const ConnectionValidationException(this.reason) : super();

  final ConnectionValidationReason reason;
}

class ConnectionSettings {
  ConnectionSettings({
    required String serverUrl,
    required String serverId,
    required String deviceId,
    required String token,
  }) : serverUrl = normalizeServerUrl(serverUrl),
       serverId = validateServerId(serverId),
       deviceId = validateDeviceId(deviceId),
       token = validateToken(token);

  final String serverUrl;
  final String serverId;
  final String deviceId;
  final String token;

  static String normalizeServerUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.incompleteServerAddress,
      );
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.disallowedUrlComponents,
      );
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const ConnectionValidationException(
        ConnectionValidationReason.originOnly,
      );
    }
    final isLoopback =
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host.toLowerCase() == 'localhost';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.httpsRequired,
      );
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static String validateToken(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^tspd_[A-Za-z0-9_-]{40,80}$').hasMatch(trimmed)) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.invalidToken,
      );
    }
    return trimmed;
  }

  static String validateServerId(String value) {
    final trimmed = value.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(trimmed)) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.invalidServerId,
      );
    }
    return trimmed;
  }

  static String validateDeviceId(String value) {
    final trimmed = value.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(trimmed)) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.invalidDeviceId,
      );
    }
    return trimmed;
  }
}
