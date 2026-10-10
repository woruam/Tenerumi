import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Conservative public-address policy, including IPv4 mapped into IPv6.
bool isPublicPluginAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
      return isPublicPluginAddress(
        InternetAddress.fromRawAddress(b.sublist(12)),
      );
    }
    // Only global unicast 2000::/3; exclude special and transition ranges.
    if ((b[0] & 0xe0) != 0x20) return false;
    if (b[0] == 0x20 &&
        b[1] == 0x01 &&
        (b[2] < 2 || (b[2] == 0x0d && b[3] == 0xb8))) {
      return false;
    }
    if (b[0] == 0x20 && b[1] == 0x02) return false; // 6to4
    if (b[0] == 0x3f && b[1] == 0xff && (b[2] & 0xf0) == 0) return false;
    return true;
  }
  if (b.length != 4) return false;
  if (b[0] == 0 ||
      b[0] == 10 ||
      b[0] == 127 ||
      b[0] >= 224 ||
      (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
      (b[0] == 169 && b[1] == 254) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 192 && b[1] == 0 && (b[2] == 0 || b[2] == 2)) ||
      (b[0] == 192 && b[1] == 88 && b[2] == 99) ||
      (b[0] == 198 && (b[1] == 18 || b[1] == 19)) ||
      (b[0] == 198 && b[1] == 51 && b[2] == 100) ||
      (b[0] == 203 && b[1] == 0 && b[2] == 113)) {
    return false;
  }
  return true;
}

Future<InternetAddress> resolvePluginAddress(
  String host, {
  Future<List<InternetAddress>> Function(String)? lookup,
}) async {
  final addresses = await (lookup ?? InternetAddress.lookup)(host)
      .timeout(const Duration(seconds: 5));
  if (addresses.isEmpty || addresses.any((a) => !isPublicPluginAddress(a))) {
    throw StateError(
      'Accesso alla rete locale o a indirizzi riservati vietato',
    );
  }
  return addresses.first;
}

http.Client createPluginHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (uri.scheme != 'https' || uri.port != 443 || proxyHost != null) {
      throw StateError('Connessione plugin non consentita');
    }
    final address = await resolvePluginAddress(uri.host);
    // Connect to the checked IP, without a second DNS lookup. HttpClient still
    // performs TLS verification against the original URI hostname.
    return Socket.startConnect(address, uri.port);
  };
  return IOClient(client);
}
