import 'plugin_limits.dart';
export 'plugin_http_stub.dart' if (dart.library.io) 'plugin_http_native.dart';

void validatePluginHttpUri(Uri uri, List<String> hosts) {
  final host = uri.host.toLowerCase();
  if (uri.scheme != 'https' ||
      uri.toString().length > 8192 ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !hosts.contains(host) ||
      !host.contains('.') ||
      RegExp(r'^[0-9.]+$').hasMatch(host) ||
      host.contains(':') ||
      [
        '.localhost',
        '.local',
        '.internal',
        '.lan',
        '.home',
        '.test',
        '.invalid',
        '.example',
      ].any(host.endsWith)) {
    throw StateError(
      'Sono consentiti soltanto server HTTPS pubblici dichiarati',
    );
  }
}

void validatePluginHttpHeaders(Map headers) {
  validatePluginValue(headers, maxBytes: 16 * 1024);
  const forbidden = {
    'host',
    'connection',
    'content-length',
    'transfer-encoding',
    'upgrade',
    'proxy-authorization',
    'proxy-connection',
  };
  for (final entry in headers.entries) {
    if (entry.key is! String ||
        entry.value is! String ||
        forbidden.contains((entry.key as String).toLowerCase()) ||
        !RegExp(r'^[!#$%&\x27*+.^_`|~a-zA-Z0-9-]+$')
            .hasMatch(entry.key as String) ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value as String)) {
      throw StateError('Header HTTP non valido o riservato');
    }
  }
}
