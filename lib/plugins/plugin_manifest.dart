import 'dart:convert';

const pluginPermissions = {
  'document.read': 'Leggere gli appunti',
  'document.write': 'Modificare gli appunti',
  'tool.write': 'Cambiare lo strumento',
  'storage': 'Conservare dati del plugin',
  'export': 'Esportare tramite il selettore file',
  'files.read': 'Aprire file scelti dall’utente',
  'network': 'Contattare i server HTTPS dichiarati',
  'ocr': 'Riconoscere testo nelle immagini',
  'ui': 'Mostrare moduli e anteprime',
};

class NotePlugin {
  final Map<String, dynamic> manifest;
  NotePlugin._(this.manifest);
  String get id => manifest['id'] as String;
  String get name => manifest['name'] as String;
  String get version => manifest['version'] as String;
  String get description => manifest['description'] as String? ?? '';
  Set<String> get permissions =>
      (manifest['permissions'] as List).cast<String>().toSet();
  List<Map<String, dynamic>> get commands =>
      (manifest['commands'] as List).cast<Map<String, dynamic>>();
  String get source => const JsonEncoder.withIndent('  ').convert(manifest);
  bool get isJavaScript => manifest['runtime'] == 'javascript';
  Map<String, String> get modules =>
      Map<String, String>.from(manifest['modules'] as Map? ?? {});

  factory NotePlugin.parse(String source) {
    if (utf8.encode(source).length > 2 * 1024 * 1024) {
      throw const FormatException('Plugin troppo grande (massimo 2 MiB)');
    }
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Il plugin deve essere un oggetto JSON');
    }
    void check(bool valid, String message) {
      if (!valid) throw FormatException(message);
    }

    check(value['apiVersion'] == 1, 'apiVersion deve essere 1');
    check(
      value['runtime'] == null ||
          ['workflow', 'javascript'].contains(value['runtime']),
      'runtime non valido',
    );
    if (value['runtime'] == 'javascript') {
      check(
        value['modules'] is Map &&
            (value['modules'] as Map).isNotEmpty &&
            (value['modules'] as Map).length <= 64,
        'modules richiede da 1 a 64 file JavaScript',
      );
      for (final entry in (value['modules'] as Map).entries) {
        check(
          entry.key is String &&
              RegExp(r'^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*\.js$')
                  .hasMatch(entry.key as String) &&
              entry.value is String,
          'Percorso o sorgente modulo non valido',
        );
      }
      check(
        (value['modules'] as Map).containsKey(value['entry'] ?? 'main.js'),
        'Modulo entry mancante',
      );
    }
    check(
      value['networkHosts'] == null ||
          value['networkHosts'] is List &&
              (value['networkHosts'] as List).length <= 16 &&
              (value['networkHosts'] as List).every(
                (h) =>
                    h is String &&
                    RegExp(r'^[a-z0-9]+([.-][a-z0-9]+)*$').hasMatch(h),
              ),
      'networkHosts deve contenere nomi di server, senza URL o wildcard',
    );
    check(
      value['id'] is String &&
          RegExp(r'^[a-z][a-z0-9._-]{2,79}$').hasMatch(value['id'] as String),
      'ID non valido: usare lettere minuscole, cifre, punti e trattini',
    );
    for (final key in ['name', 'version']) {
      check(
        value[key] is String &&
            (value[key] as String).trim().isNotEmpty &&
            (value[key] as String).length <= 120,
        '$key mancante o troppo lungo',
      );
    }
    check(
      value['description'] == null || value['description'] is String,
      'description deve essere testo',
    );
    check(
      value['permissions'] is List &&
          (value['permissions'] as List).every(
            (p) => pluginPermissions.containsKey(p),
          ),
      'Permessi non validi',
    );
    check(
      value['commands'] is List &&
          (value['commands'] as List).isNotEmpty &&
          (value['commands'] as List).length <= 32,
      'Servono da 1 a 32 comandi',
    );
    final ids = <String>{};
    void validateSteps(dynamic steps, int depth) {
      check(
        depth <= 24 && steps is List && steps.length <= 2000,
        'Elenco steps non valido o troppo complesso',
      );
      for (final step in steps as List) {
        check(step is Map<String, dynamic>, 'Ogni step deve essere un oggetto');
        final map = step as Map<String, dynamic>;
        final keys = [
          'action',
          'set',
          'if',
          'repeat',
          'forEach',
        ].where(map.containsKey).toList();
        check(
          keys.length == 1,
          'Ogni step richiede una sola fra action, set, if, repeat, forEach',
        );
        if (map.containsKey('action')) {
          check(
            map['action'] is String &&
                (map['args'] == null || map['args'] is Map),
            'action/args non validi',
          );
        }
        if (map.containsKey('set')) {
          check(
            map['set'] is String && map.containsKey('value'),
            'set richiede un nome e value',
          );
        }
        if (map.containsKey('if')) {
          validateSteps(map['then'], depth + 1);
          if (map['else'] != null) validateSteps(map['else'], depth + 1);
        }
        if (map.containsKey('repeat') || map.containsKey('forEach')) {
          check(map['as'] is String, 'Il ciclo richiede as');
          validateSteps(map['steps'], depth + 1);
        }
      }
    }

    for (final command in value['commands'] as List) {
      check(command is Map<String, dynamic>, 'Comando non valido');
      final c = command as Map<String, dynamic>;
      check(
        c['id'] is String &&
            RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(c['id'] as String) &&
            ids.add(c['id'] as String),
        'ID comando non valido o duplicato',
      );
      check(
        c['label'] is String && (c['label'] as String).trim().isNotEmpty,
        'Il comando richiede label',
      );
      check(
        c['inputs'] == null ||
            c['inputs'] is List && (c['inputs'] as List).length <= 32,
        'inputs non validi',
      );
      final fields = <String>{};
      for (final field in c['inputs'] as List? ?? []) {
        check(field is Map<String, dynamic>, 'Campo non valido');
        final f = field as Map<String, dynamic>;
        check(
          f['id'] is String &&
              RegExp(r'^[a-z][a-zA-Z0-9_]{0,63}$')
                  .hasMatch(f['id'] as String) &&
              fields.add(f['id'] as String),
          'ID campo non valido o duplicato',
        );
        check(
          f['label'] is String &&
              ['text', 'number', 'boolean', 'choice'].contains(f['type']),
          'label/type campo non validi',
        );
        if (f['type'] == 'choice') {
          check(
            f['options'] is List &&
                (f['options'] as List).isNotEmpty &&
                (f['options'] as List).every((v) => v is String),
            'choice richiede options testuali',
          );
        }
      }
      if (value['runtime'] == 'javascript') {
        check(
          c['handler'] is String &&
              RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$')
                  .hasMatch(c['handler'] as String),
          'handler deve essere il nome di una funzione esportata',
        );
        check(
          !c.containsKey('steps'),
          'Un comando JavaScript usa handler, senza steps',
        );
      } else {
        validateSteps(c['steps'], 0);
      }
    }
    return NotePlugin._(value);
  }
}
