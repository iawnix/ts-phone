enum ConnectionValidationReason {
  incompleteServerAddress,
  disallowedUrlComponents,
  originOnly,
  httpsRequired,
  invalidToken,
}

class ConnectionValidationException extends FormatException {
  const ConnectionValidationException(this.reason) : super();

  final ConnectionValidationReason reason;
}

class ConnectionSettings {
  ConnectionSettings({required String serverUrl, required String token})
    : serverUrl = normalizeServerUrl(serverUrl),
      token = validateToken(token);

  final String serverUrl;
  final String token;

  Uri endpoint(String path) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse(serverUrl).replace(path: '/api/v4/$normalizedPath');
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
    if (!RegExp(r'^[A-Za-z0-9_-]{40,100}$').hasMatch(trimmed)) {
      throw const ConnectionValidationException(
        ConnectionValidationReason.invalidToken,
      );
    }
    return trimmed;
  }
}
