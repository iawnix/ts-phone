enum ConnectionValidationReason {
  incompleteServerAddress,
  disallowedUrlComponents,
  originOnly,
  httpsRequired,
  invalidServerId,
  invalidToken,
}

class ConnectionValidationException extends FormatException {
  const ConnectionValidationException(this.reason) : super();

  final ConnectionValidationReason reason;
}

class ConnectionSettings {
  ConnectionSettings({
    required String serverUrl,
    String serverId = '00000000-0000-4000-8000-000000000000',
    required String token,
  }) : serverUrl = normalizeServerUrl(serverUrl),
       serverId = validateServerId(serverId),
       token = validateToken(token);

  final String serverUrl;
  final String serverId;
  final String token;

  /// Returns a path on the configured Radius origin for diagnostics and
  /// tooling. App Server traffic itself always uses the Pi Radius WebSocket
  /// route built by [PiAppServerClient], never a legacy REST endpoint.
  Uri endpoint(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(serverUrl).replace(path: normalizedPath);
  }

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
    if (trimmed.length < 40 ||
        trimmed.length > 4096 ||
        trimmed.codeUnits.any((value) => value <= 32 || value == 127)) {
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
}
