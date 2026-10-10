import 'package:http/http.dart' as http;

http.Client createPluginHttpClient() => throw UnsupportedError(
  'Rete dei plugin disponibile su Android e desktop: il browser non consente '
  'di verificare e vincolare gli indirizzi DNS della connessione.',
);
