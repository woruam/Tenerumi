import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/editing_tool.dart';

import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'plugin_services.dart';
import 'plugin_limits.dart';

class InstalledPlugin {
  final NotePlugin plugin;
  final bool enabled;
  final Map<String, dynamic> state;
  InstalledPlugin(
    this.plugin, {
    this.enabled = true,
    Map<String, dynamic>? state,
  }) : state = state ?? {};
}

/// A staged transaction. Host extensions must edit this content, not the canvas,
/// to retain rollback and one-step undo semantics.
class PluginSession {
  final CanvasController canvas;
  final int pageIndex;
  final int layerIndex;
  final List<XppContent?> content;
  final Map<String, dynamic> state;
  final List<String> messages = [];
  final List<String> exports = [];
  final List<PluginOutput> files = [];
  NotePlugin? plugin;
  PluginHost? host;
  bool active = true;
  Map<String, dynamic>? tool;
  bool changed = false;
  int calls = 0, generatedBytes = 0, generatedPoints = 0;
  final List<void Function()> cleanup = [];
  void ensureActive() {
    if (!active) throw StateError('Sessione plugin terminata');
  }

  void finish() {
    active = false;
    for (final close in cleanup) {
      try {
        close();
      } catch (_) {}
    }
    cleanup.clear();
  }

  void reserve({int bytes = 0, int points = 0}) {
    ensureActive();
    generatedBytes += bytes;
    generatedPoints += points;
    if (generatedBytes > 32 * 1024 * 1024 || generatedPoints > 100000) {
      throw StateError('Comando troppo grande: suddividerlo in più esecuzioni');
    }
  }

  PluginSession(this.canvas, this.pageIndex, Map<String, dynamic> storedState)
    : layerIndex = canvas.activeLayerIndex(pageIndex),
      content = cloneContents(canvas.activeLayer(pageIndex).content ?? []),
      state = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(storedState)) as Map,
      );
  double number(Map<String, dynamic> args, String key, double fallback) {
    final value = args[key] ?? fallback;
    if (value is! num || !value.isFinite || value.abs() > 100000) {
      throw StateError('Numero non valido: $key');
    }
    return value.toDouble();
  }

  Color color(Map<String, dynamic> args) {
    final value = args['color'] ?? '#000000';
    if (value is! String ||
        !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)) {
      throw StateError('color richiede #RRGGBB o #AARRGGBB');
    }
    return Color(
      int.parse(value.substring(1), radix: 16) |
          (value.length == 7 ? 0xFF000000 : 0),
    );
  }

  List<int> ids(Map<String, dynamic> args) {
    final value = args['ids'];
    if (value == 'all') return List.generate(content.length, (i) => i);
    if (value is! List ||
        value.any((v) => v is! int || v < 0 || v >= content.length)) {
      throw StateError('ids richiede indici validi o "all"');
    }
    return value.cast<int>().toSet().toList();
  }

  int add(XppContent element) {
    if (!active) throw StateError('Sessione plugin terminata');
    if (content.length >= 10000) {
      throw StateError('Massimo 10000 elementi nella pagina');
    }
    if (element is XppText) {
      reserve(bytes: utf8.encode(pluginText(element.text)).length);
    }
    if (element is XppStroke) reserve(points: element.points?.length ?? 0);
    content.add(element);
    changed = true;
    return content.length - 1;
  }

  List<Map<String, dynamic>> describeContent() => [
    for (var i = 0; i < content.length; i++)
      if (content[i] != null)
        {
          'id': i,
          'type': content[i] is XppText
              ? 'text'
              : content[i] is XppStroke
              ? 'stroke'
              : content[i] is XppImage
              ? 'image'
              : 'tex',
          'text': content[i] is XppText
              ? (content[i] as XppText).text
              : content[i] is XppTexImage
              ? (content[i] as XppTexImage).text
              : null,
          'x': content[i]!.bounds()?.left,
          'y': content[i]!.bounds()?.top,
          'width': content[i]!.bounds()?.width,
          'height': content[i]!.bounds()?.height,
        },
  ];
}

class PluginController extends ChangeNotifier {
  static const storageKey = 'osipp.plugins.v1';
  final void Function(PluginApi, PluginSession?)? extendApi;
  Completer<void>? _cancel;
  PluginSession? _session;
  void cancel() {
    _session?.finish();
    if (_cancel?.isCompleted == false) _cancel!.complete();
  }

  PluginController({this.extendApi});
  List<InstalledPlugin> _installed = [];
  List<InstalledPlugin> get installed => List.unmodifiable(_installed);
  static const builtInKey = 'osipp.builtin-plugins.v1';
  bool pomodoroEnabled = false;
  bool? _ankiEnabled;
  bool get ankiEnabled =>
      _ankiEnabled ??
      _installed.any((e) => e.plugin.id == 'example.anki' && e.enabled);
  List<Map<String, dynamic>> get legacyAnkiCards => [
    for (final e in _installed.where((e) => e.plugin.id == 'example.anki'))
      if (e.state['cards'] is List)
        for (final c in e.state['cards'] as List)
          if (c is Map && c['front'] is String && c['back'] is String)
            Map<String, dynamic>.from(c),
  ];

  Future<void> setBuiltInEnabled(String id, bool enabled) async {
    if (!['pomodoro', 'anki'].contains(id)) throw ArgumentError.value(id);
    await load();
    return _exclusive(() async {
      final prefs = await SharedPreferences.getInstance();
      final values = {
        'pomodoro': id == 'pomodoro' ? enabled : pomodoroEnabled,
        'anki': id == 'anki' ? enabled : ankiEnabled,
      };
      if (!await prefs.setString(builtInKey, jsonEncode(values))) {
        throw StateError('Impossibile conservare le impostazioni plugin');
      }
      pomodoroEnabled = values['pomodoro']!;
      _ankiEnabled = values['anki'];
    });
  }

  final List<String> loadErrors = [];
  bool running = false;
  bool loading = false;
  bool _disposed = false;
  Future<void>? _load;
  Future<void> load() => _load ??= _loadStored();
  Future<void> _loadStored() async {
    loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        final builtIns = jsonDecode(prefs.getString(builtInKey) ?? '{}');
        if (builtIns is Map) {
          pomodoroEnabled = builtIns['pomodoro'] == true;
          _ankiEnabled = builtIns['anki'] is bool
              ? builtIns['anki'] as bool
              : null;
        }
      } catch (error) {
        loadErrors.add('Impostazioni plugin integrati: $error');
      }
      final stored = prefs.getString(storageKey) ?? '[]';
      if (utf8.encode(stored).length > 8 * 1024 * 1024) {
        throw const FormatException('Archivio plugin troppo grande');
      }
      final raw = jsonDecode(stored);
      if (raw is! List || raw.length > 32) {
        throw const FormatException('Archivio plugin non valido');
      }
      final loaded = <InstalledPlugin>[];
      for (final entry in raw) {
        try {
          validatePluginValue(entry['state'] ?? {}, maxBytes: 65536);
          final plugin = NotePlugin.parse(jsonEncode(entry['manifest']));
          _api(null).validate(plugin);
          if (loaded.any((p) => p.plugin.id == plugin.id)) {
            throw const FormatException('ID duplicato');
          }
          loaded.add(
            InstalledPlugin(
              plugin,
              enabled: entry['enabled'] == true,
              state: Map<String, dynamic>.from(entry['state'] as Map? ?? {}),
            ),
          );
        } catch (error) {
          loadErrors.add('$error');
        }
      }
      if (!_disposed) _installed = loaded;
    } catch (error) {
      loadErrors.add('$error');
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _persist(List<InstalledPlugin> entries) async {
    if (entries.length > 32) throw StateError('Massimo 32 plugin installati');
    final json = jsonEncode([
      for (final entry in entries)
        {
          'manifest': entry.plugin.manifest,
          'enabled': entry.enabled,
          'state': entry.state,
        },
    ]);
    if (utf8.encode(json).length > 8 * 1024 * 1024) {
      throw StateError('Archivio plugin troppo grande');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(storageKey, json)) {
      throw StateError('Impossibile conservare i plugin');
    }
  }

  Future<void> _exclusive(Future<void> Function() operation) async {
    if (running) throw StateError('Un’operazione plugin è già in corso');
    running = true;
    if (!_disposed) notifyListeners();
    try {
      await operation();
    } finally {
      running = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> install(String source, {bool replace = false}) async {
    await load();
    return _exclusive(() async {
      final plugin = validateSource(source);
      final old = _installed.where((p) => p.plugin.id == plugin.id).firstOrNull;
      if (old != null && !replace) {
        throw StateError(
          'ID già installato: modifica il plugin o usa un altro ID',
        );
      }
      final entries = [
        for (final item in _installed)
          if (item.plugin.id != plugin.id) item,
        InstalledPlugin(
          plugin,
          enabled: old?.enabled ?? true,
          state: old?.state,
        ),
      ];
      await _persist(entries);
      if (!_disposed) {
        _installed = entries;
        notifyListeners();
      }
    });
  }

  NotePlugin validateSource(String source) {
    final plugin = NotePlugin.parse(source);
    _api(null).validate(plugin);
    return plugin;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await load();
    return _exclusive(() async {
      final entries = [
        for (final e in _installed)
          e.plugin.id == id
              ? InstalledPlugin(e.plugin, enabled: enabled, state: e.state)
              : e,
      ];
      await _persist(entries);
      _installed = entries;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> uninstall(String id) async {
    await load();
    return _exclusive(() async {
      final entries = _installed.where((p) => p.plugin.id != id).toList();
      await _persist(entries);
      _installed = entries;
      if (!_disposed) notifyListeners();
    });
  }

  PluginApi _api(PluginSession? s) {
    final api = PluginApi(
      beforeInvoke: () {
        s!.ensureActive();
        if (++s.calls > 2000) throw StateError('Troppe chiamate API');
      },
      afterInvoke: () => s!.ensureActive(),
      onFailure: () => s?.finish(),
    );
    void action(String name, Set<String> permissions, PluginAction run) =>
        api.register(name, permissions, run);
    action('message', {}, (a) {
      final text = '${a['text'] ?? ''}';
      if (text.length > 4096 || s!.messages.length >= 20) {
        throw StateError('Troppi messaggi');
      }
      s.messages.add(text);
      return null;
    });
    action(
      'text.add',
      {'document.write'},
      (a) => s!.add(
        XppText(
          text: pluginText(a['text']),
          offset: Offset(s.number(a, 'x', 40), s.number(a, 'y', 40)),
          size: s.number(a, 'size', 16).clamp(1, 512),
          color: s.color(a),
          fontFamily: a['font'] as String? ?? 'Sans',
        ),
      ),
    );
    action('tex.add', {'document.write'}, (a) async {
      final image = await api.invoke(s!.plugin!, 'latex.render', a) as Map;
      return api.invoke(s.plugin!, 'image.add', {
        ...a,
        ...Map<String, dynamic>.from(image),
      });
    });
    action('image.add', {'document.write'}, (a) async {
      final session = s!;
      final bytes = pluginBytes(a);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width * descriptor.height > 4000000) {
            throw StateError('Immagine plugin: massimo 4 milioni di pixel');
          }
          session.reserve(
            bytes: bytes.length + descriptor.width * descriptor.height * 4,
          );
          final codec = await descriptor.instantiateCodec();
          try {
            (await codec.getNextFrame()).image.dispose();
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      return session.add(
        XppImage(
          data: bytes,
          topLeft: Offset(
            session.number(a, 'x', 40),
            session.number(a, 'y', 40),
          ),
          bottomRight: Offset(
            session.number(a, 'x', 40) +
                session.number(a, 'width', 100).clamp(1, 10000),
            session.number(a, 'y', 40) +
                session.number(a, 'height', 100).clamp(1, 10000),
          ),
        ),
      );
    });
    action('stroke.add', {'document.write'}, (a) {
      final raw = a['points'];
      if (raw is! List || raw.isEmpty || raw.length > 10000) {
        throw StateError('points richiede da 1 a 10000 punti');
      }
      final width = s!.number(a, 'width', 2).clamp(.1, 512).toDouble();
      final highlight = a['tool'] == 'highlighter';
      return s.add(
        XppStroke.byTool(
          tool: highlight ? XppStrokeTool.HIGHLIGHTER : XppStrokeTool.PEN,
          color: highlight ? s.color(a).withValues(alpha: .5) : s.color(a),
          isShape: a['shape'] != false,
          smooth: a['smooth'] == true,
          points: [
            for (final point in raw)
              XppStrokePoint(
                x: s.number(Map<String, dynamic>.from(point as Map), 'x', 0),
                y: s.number(Map<String, dynamic>.from(point), 'y', 0),
                width: width,
              ),
          ],
        ),
      );
    });
    action('shape.add', {'document.write'}, (a) {
      final x = s!.number(a, 'x', 40), y = s.number(a, 'y', 40);
      final w = s.number(a, 'width', 120), h = s.number(a, 'height', 80);
      final kind = a['kind'] ?? 'rectangle';
      final points = switch (kind) {
        'rectangle' => [
          Offset(x, y),
          Offset(x + w, y),
          Offset(x + w, y + h),
          Offset(x, y + h),
          Offset(x, y),
        ],
        'line' => [Offset(x, y), Offset(x + w, y + h)],
        'ellipse' => [
          for (var i = 0; i <= 64; i++)
            Offset(
              x + w / 2 + w / 2 * math.cos(i * math.pi / 32),
              y + h / 2 + h / 2 * math.sin(i * math.pi / 32),
            ),
        ],
        _ => throw StateError('Forma sconosciuta: $kind'),
      };
      return s.add(
        XppStroke.byTool(
          tool: XppStrokeTool.PEN,
          color: s.color(a),
          isShape: true,
          smooth: kind == 'ellipse',
          points: [
            for (final p in points)
              XppStrokePoint(
                x: p.dx,
                y: p.dy,
                width: s.number(a, 'strokeWidth', 2).clamp(.1, 512).toDouble(),
              ),
          ],
        ),
      );
    });
    action('content.list', {'document.read'}, (_) => s!.describeContent());
    action('content.delete', {'document.write'}, (a) {
      final ids = s!.ids(a)..sort((a, b) => b.compareTo(a));
      for (final id in ids) {
        s.content.removeAt(id);
      }
      s.changed = s.changed || ids.isNotEmpty;
      return null;
    });
    action('content.transform', {'document.write'}, (a) {
      final scale = s!.number(a, 'scale', 1);
      if (scale <= 0 || scale > 100) {
        throw StateError('scale richiede un numero > 0 e <= 100');
      }
      for (final id in s.ids(a)) {
        s.content[id]?.scaleBy(
          scale,
          Offset(s.number(a, 'anchorX', 0), s.number(a, 'anchorY', 0)),
        );
        s.content[id]?.translate(
          Offset(s.number(a, 'dx', 0), s.number(a, 'dy', 0)),
        );
        final bounds = s.content[id]?.bounds();
        if (bounds != null &&
            [
              bounds.left,
              bounds.top,
              bounds.right,
              bounds.bottom,
            ].any((v) => !v.isFinite || v.abs() > 100000)) {
          throw StateError('La trasformazione supera i limiti del foglio');
        }
        s.changed = true;
      }
      return null;
    });
    action('text.update', {'document.write'}, (a) {
      final id = a['id'];
      if (id is! int ||
          id < 0 ||
          id >= s!.content.length ||
          s.content[id] is! XppText) {
        throw StateError('id deve indicare un testo');
      }
      final text = pluginText(a['text']);
      s.reserve(bytes: utf8.encode(text).length);
      (s.content[id] as XppText).text = text;
      s.changed = true;
      return null;
    });
    action('tool.set', {'tool.write'}, (a) {
      if (![
        'pen',
        'highlighter',
        'eraser',
        'lasso',
        'hand',
        'text',
      ].contains(a['tool'])) {
        throw StateError('Strumento sconosciuto');
      }
      s!.number(a, 'width', 2);
      s.color(a);
      s.tool = a;
      return null;
    });
    action('state.get', {'storage'}, (a) => s!.state[a['key'] as String]);
    action('state.set', {'storage'}, (a) {
      final key = a['key'] as String;
      if (key.isEmpty || key.length > 120) {
        throw StateError('Chiave non valida');
      }
      s!.state[key] = a['value'];
      if (utf8.encode(jsonEncode(s.state)).length > 65536) {
        throw StateError('Dati plugin: massimo 64 KiB');
      }
      return null;
    });
    for (final format in ['pdf', 'xopp']) {
      action('export.$format', {'export', 'document.read'}, (_) {
        if (s!.exports.isNotEmpty) {
          throw StateError('Un solo export per comando');
        }
        s.exports.add(format);
        return null;
      });
    }
    registerPluginServices(api, s);
    extendApi?.call(api, s);
    return api;
  }

  Future<PluginSession> execute(
    String id,
    String commandId,
    CanvasController canvas, {
    int pageIndex = 0,
    Map<String, dynamic> input = const {},
    PluginHost? host,
  }) async {
    if (running || canvas.savingFile || !canvas.acceptsPluginEdits) {
      throw StateError('Attendere la fine dell’operazione in corso');
    }
    final entry = _installed.where((p) => p.plugin.id == id).firstOrNull;
    if (entry == null || !entry.enabled) throw StateError('Plugin non attivo');
    if (entry.plugin.isJavaScript) {
      throw UnsupportedError(
        'JavaScript sospeso per sicurezza. Usa un workflow JSON.',
      );
    }
    final command = entry.plugin.commands
        .where((c) => c['id'] == commandId)
        .firstOrNull;
    if (command == null) throw StateError('Comando inesistente');
    if (canvas.file?.pages == null ||
        pageIndex < 0 ||
        pageIndex >= canvas.file!.pages!.length) {
      throw StateError('Pagina non valida');
    }
    final values = <String, dynamic>{};
    for (final f in command['inputs'] as List? ?? []) {
      final field = f as Map;
      final value = input[field['id']] ?? field['default'];
      if (field['required'] == true && (value == null || value == '')) {
        throw StateError('Compilare ${field['label']}');
      }
      final valid = switch (field['type']) {
        'text' => value == null || value is String,
        'number' => value is num && value.isFinite,
        'boolean' => value is bool,
        'choice' => (field['options'] as List).contains(value),
        _ => false,
      };
      if (!valid) throw StateError('Valore non valido per ${field['label']}');
      values[field['id'] as String] = value;
    }
    validatePluginValue(values, maxBytes: 2 * 1024 * 1024);
    final session = PluginSession(canvas, pageIndex, entry.state);
    session.plugin = entry.plugin;
    session.host = host;
    if (host?.close != null) session.cleanup.add(host!.close!);
    final page = canvas.file!.pages![pageIndex];
    final originalRevision = canvas.pluginRevision;
    final api = _api(session);
    api.validate(entry.plugin);
    running = true;
    _cancel = Completer<void>();
    _session = session;
    notifyListeners();
    try {
      final context = <String, dynamic>{
        'input': values,
        'today': DateTime.now().toIso8601String().substring(0, 10),
        'page': {
          'index': pageIndex,
          'number': pageIndex + 1,
          'width': page.pageSize!.width,
          'height': page.pageSize!.height,
          'infinite': page.infinite,
          'layerIndex': session.layerIndex,
          'layerName': page.layers![session.layerIndex].name,
        },
        if (entry.plugin.permissions.contains('document.read'))
          'document': {
            'title': canvas.file!.title,
            'pageCount': canvas.file!.pages!.length,
            'contents': session.describeContent(),
          },
      };
      final runtime = PluginRuntime(
        entry.plugin,
        api,
        context,
        cancelled: () => !session.active,
      );
      final operation = runtime.run(command['steps'] as List);
      await Future.any([
        operation,
        _cancel!.future.then<void>(
          (_) => throw StateError('Comando annullato'),
        ),
      ]).timeout(const Duration(minutes: 2));
      if (_cancel!.isCompleted) throw StateError('Comando annullato');
      session.ensureActive();
      session.finish();
      if (_disposed ||
          !canvas.acceptsPluginEdits ||
          canvas.pluginRevision != originalRevision ||
          canvas.file!.pages![pageIndex] != page) {
        throw StateError('Documento cambiato durante l’esecuzione: riprovare');
      }
      if (session.changed && !canvas.canEditLayer(pageIndex)) {
        throw StateError('Livello bloccato o nascosto');
      }
      final entries = [
        for (final e in _installed)
          e.plugin.id == id
              ? InstalledPlugin(
                  e.plugin,
                  enabled: e.enabled,
                  state: session.state,
                )
              : e,
      ];
      await _persist(entries);
      if (_disposed ||
          _cancel!.isCompleted ||
          !canvas.acceptsPluginEdits ||
          canvas.pluginRevision != originalRevision) {
        await _persist(_installed);
        throw StateError('Documento cambiato durante l’esecuzione: riprovare');
      }
      if (session.changed) {
        canvas.saveSnapshot(pageIndex);
        page.layers![session.layerIndex].content = session.content;
        canvas.markContentChanged(pageIndex);
      }
      if (session.tool case final Map<String, dynamic> a) {
        final tool = switch (a['tool']) {
          'pen' => EditingTool.STYLUS,
          'highlighter' => EditingTool.HIGHLIGHT,
          'eraser' => EditingTool.ERASER,
          'lasso' => EditingTool.SELECT,
          'hand' => EditingTool.MOVE,
          _ => EditingTool.TEXT,
        };
        if (a.containsKey('width') || a.containsKey('color')) {
          if (tool == EditingTool.STYLUS) {
            canvas.setPenProps(
              a.containsKey('color') ? session.color(a) : null,
              a.containsKey('width')
                  ? session.number(a, 'width', 2).clamp(.1, 512).toDouble()
                  : null,
            );
          }
          if (tool == EditingTool.HIGHLIGHT) {
            canvas.setHighlighterProps(
              a.containsKey('color') ? session.color(a) : null,
              a.containsKey('width')
                  ? session.number(a, 'width', 15).clamp(.1, 512).toDouble()
                  : null,
            );
          }
        }
        canvas.setTool(tool);
      }
      _installed = entries;
      return session;
    } finally {
      session.finish();
      if (_cancel?.isCompleted == false) _cancel!.complete();
      _cancel = null;
      _session = null;
      running = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    super.dispose();
  }
}
