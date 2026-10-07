import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'plugin_controller.dart';
import 'plugin_examples.dart';
import 'plugin_manifest.dart';
import 'plugin_package.dart';
import 'plugin_ui.dart';

class PluginManagerPage extends StatefulWidget {
  final PluginController plugins;
  final CanvasController? canvas;
  const PluginManagerPage({super.key, required this.plugins, this.canvas});
  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _edit({String? source, bool replace = false}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PluginEditor(
        source: source,
        validate: widget.plugins.validateSource,
      ),
    );
    if (result == null) return;
    try {
      await widget.plugins.install(result, replace: replace);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _import() async {
    try {
      final data = await FilePickerCross.importFromStorage(
        type: FileTypeCross.custom,
        fileExtension: 'json,osiplugin',
      );
      if (!mounted) return;
      await _edit(source: decodePluginPackage(data.toUint8List()).source);
    } catch (error) {
      if (error != 'No file selected.') _error(error);
    }
  }

  Future<void> _examples() async {
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Esempi pronti'),
        children: [
          for (var i = 0; i < pluginExamples.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Text(pluginExamples[i]['name'] as String),
            ),
        ],
      ),
    );
    if (choice != null && mounted) await _edit(source: exampleSource(choice));
  }

  Future<void> _export(NotePlugin plugin) async {
    try {
      await FilePickerCross(
        Uint8List.fromList(utf8.encode(plugin.source)),
        path: '${plugin.id}.osiplugin.json',
      ).exportToStorage();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _run(InstalledPlugin entry, Map<String, dynamic> command) async {
    final canvas = widget.canvas;
    if (canvas == null) return;
    final input = await showDialog<_PluginInput>(
      context: context,
      builder: (_) => _CommandForm(command: command, canvas: canvas),
    );
    if (input == null || !mounted) return;
    try {
      final result = await widget.plugins.execute(
        entry.plugin.id,
        command['id'] as String,
        canvas,
        pageIndex: input.page,
        input: input.values,
        host: pluginUiHost(context),
      );
      if (!mounted) return;
      for (final file in result.files) {
        await FilePickerCross(file.bytes, path: file.name).exportToStorage();
        if (!mounted) return;
      }
      for (final format in result.exports) {
        if (format == 'pdf') {
          await canvas.exportToPdf(context);
        } else {
          await canvas.exportToXopp(context);
        }
        if (!mounted) return;
      }
      if (result.messages.isNotEmpty || result.exports.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.messages.isEmpty
                  ? 'Comando completato'
                  : result.messages.join('\n'),
            ),
          ),
        );
      }
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.plugins,
    builder: (context, _) {
      final plugins = widget.plugins;
      return Scaffold(
        appBar: AppBar(title: const Text('Plugin')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (plugins.running)
              TextButton.icon(
                onPressed: plugins.cancel,
                icon: const Icon(Icons.stop),
                label: const Text('Annulla esecuzione'),
              ),
            const Text(
              'Crea un plugin guidato o importa un plugin programmabile .osiplugin. Apri un documento per eseguire i comandi.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('plugin-create'),
                  onPressed: plugins.running || plugins.loading
                      ? null
                      : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Crea plugin'),
                ),
                OutlinedButton.icon(
                  onPressed: plugins.running || plugins.loading
                      ? null
                      : _import,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Importa'),
                ),
                OutlinedButton.icon(
                  onPressed: plugins.running || plugins.loading
                      ? null
                      : _examples,
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Esempi'),
                ),
              ],
            ),
            if (plugins.running || plugins.loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            for (final error in plugins.loadErrors)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Plugin non caricato: $error'),
              ),
            if (plugins.installed.isEmpty && !plugins.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nessun plugin installato. Prova gli esempi o creane uno.',
                ),
              ),
            for (final entry in plugins.installed)
              Card(
                child: ExpansionTile(
                  title: Text(entry.plugin.name),
                  subtitle: Text(
                    '${entry.plugin.version} · ${entry.enabled ? 'Attivo' : 'Disattivato'}',
                  ),
                  trailing: Switch(
                    value: entry.enabled,
                    onChanged: plugins.running
                        ? null
                        : (value) async {
                            try {
                              await plugins.setEnabled(entry.plugin.id, value);
                            } catch (e) {
                              _error(e);
                            }
                          },
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.plugin.description),
                          const SizedBox(height: 8),
                          Text(
                            'Accesso: ${entry.plugin.permissions.isEmpty ? 'solo messaggi' : entry.plugin.permissions.map((p) => pluginPermissions[p]).join(', ')}',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final command in entry.plugin.commands)
                                FilledButton.tonal(
                                  onPressed:
                                      !entry.enabled ||
                                          plugins.running ||
                                          widget.canvas == null
                                      ? null
                                      : () => _run(entry, command),
                                  child: Text(command['label'] as String),
                                ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: plugins.running
                                    ? null
                                    : () => _edit(
                                        source: entry.plugin.source,
                                        replace: true,
                                      ),
                                child: const Text('Modifica JSON'),
                              ),
                              TextButton(
                                onPressed: plugins.running
                                    ? null
                                    : () => _export(entry.plugin),
                                child: const Text('Condividi file'),
                              ),
                              TextButton(
                                onPressed: plugins.running
                                    ? null
                                    : () async {
                                        try {
                                          await plugins.uninstall(
                                            entry.plugin.id,
                                          );
                                        } catch (e) {
                                          _error(e);
                                        }
                                      },
                                child: const Text('Rimuovi'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _PluginEditor extends StatefulWidget {
  final String? source;
  final NotePlugin Function(String) validate;
  const _PluginEditor({this.source, required this.validate});
  @override
  State<_PluginEditor> createState() => _PluginEditorState();
}

class _PluginEditorState extends State<_PluginEditor> {
  final name = TextEditingController(text: 'Il mio plugin');
  final text = TextEditingController(text: 'Appunti');
  final code = TextEditingController();
  bool advanced = false;
  String action = 'text.add';
  String? error;
  @override
  void initState() {
    super.initState();
    advanced = widget.source != null;
    code.text = widget.source ?? '';
  }

  String _guided() => const JsonEncoder.withIndent('  ').convert({
    'apiVersion': 1,
    'id': 'custom.plugin-${DateTime.now().microsecondsSinceEpoch}',
    'name': name.text,
    'version': '1.0.0',
    'description': 'Creato con l’editor guidato',
    'permissions': switch (action) {
      'text.add' || 'shape.add' => ['document.write'],
      'tool.set' => ['tool.write'],
      _ => [],
    },
    'commands': [
      {
        'id': 'run',
        'label': name.text,
        'steps': [
          {
            'action': action,
            'args': switch (action) {
              'text.add' => {'text': text.text, 'x': 40, 'y': 40, 'size': 18},
              'shape.add' => {
                'kind': 'rectangle',
                'x': 40,
                'y': 40,
                'width': 160,
                'height': 100,
                'color': '#1565C0',
              },
              'tool.set' => {
                'tool': 'highlighter',
                'width': 18,
                'color': '#FFF59D',
              },
              _ => {'text': text.text},
            },
          },
        ],
      },
    ],
  });
  void _save() {
    try {
      final source = advanced ? code.text : _guided();
      widget.validate(source);
      Navigator.pop(context, source);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    name.dispose();
    text.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Editor plugin'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!advanced) ...[
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome del plugin'),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: action,
                decoration: const InputDecoration(labelText: 'Cosa deve fare?'),
                items: const [
                  DropdownMenuItem(
                    value: 'text.add',
                    child: Text('Inserire un testo'),
                  ),
                  DropdownMenuItem(
                    value: 'shape.add',
                    child: Text('Disegnare un riquadro'),
                  ),
                  DropdownMenuItem(
                    value: 'tool.set',
                    child: Text('Preparare un evidenziatore'),
                  ),
                  DropdownMenuItem(
                    value: 'message',
                    child: Text('Mostrare un messaggio'),
                  ),
                ],
                onChanged: (value) => setState(() => action = value!),
              ),
              if (action == 'text.add' || action == 'message')
                TextField(
                  controller: text,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: r'Testo (puoi usare ${today} per la data)',
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Per coordinate, forme, moduli e logica personalizzati apri la modalità JSON.',
              ),
              TextButton(
                onPressed: () {
                  code.text = _guided();
                  setState(() => advanced = true);
                },
                child: const Text('Apri editor JSON avanzato'),
              ),
            ] else
              TextField(
                key: const ValueKey('plugin-source'),
                controller: code,
                minLines: 12,
                maxLines: 20,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Plugin JSON',
                  border: OutlineInputBorder(),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _save, child: const Text('Installa')),
    ],
  );
}

class _PluginInput {
  final int page;
  final Map<String, dynamic> values;
  _PluginInput(this.page, this.values);
}

class _CommandForm extends StatefulWidget {
  final Map<String, dynamic> command;
  final CanvasController canvas;
  const _CommandForm({required this.command, required this.canvas});
  @override
  State<_CommandForm> createState() => _CommandFormState();
}

class _CommandFormState extends State<_CommandForm> {
  final form = GlobalKey<FormState>();
  final values = <String, dynamic>{};
  final editors = <TextEditingController>[];
  late int page;
  @override
  void initState() {
    super.initState();
    page = widget.canvas.activePageIndex.clamp(
      0,
      widget.canvas.file!.pages!.length - 1,
    );
  }

  @override
  void dispose() {
    for (final editor in editors) {
      editor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.command['label'] as String),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: page,
                decoration: const InputDecoration(
                  labelText: 'Pagina degli appunti',
                ),
                items: [
                  for (var i = 0; i < widget.canvas.file!.pages!.length; i++)
                    DropdownMenuItem(value: i, child: Text('Pagina ${i + 1}')),
                ],
                onChanged: (v) => page = v!,
              ),
              for (final raw in widget.command['inputs'] as List? ?? [])
                _field(Map<String, dynamic>.from(raw as Map)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            form.currentState!.save();
            Navigator.pop(context, _PluginInput(page, values));
          }
        },
        child: const Text('Esegui'),
      ),
    ],
  );
  Widget _field(Map<String, dynamic> field) {
    final id = field['id'] as String, label = field['label'] as String;
    final defaultValue = field['default'];
    if (field['type'] == 'boolean') {
      values.putIfAbsent(id, () => defaultValue == true);
      return SwitchListTile(
        title: Text(label),
        value: values[id] as bool,
        onChanged: (v) => setState(() => values[id] = v),
      );
    }
    if (field['type'] == 'choice') {
      final options = (field['options'] as List).cast<String>();
      values.putIfAbsent(
        id,
        () => options.contains(defaultValue) ? defaultValue : options.first,
      );
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: values[id] as String,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final v in options) DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: (v) => values[id] = v,
      );
    }
    return TextFormField(
      initialValue:
          '${values[id] ?? defaultValue ?? (field['type'] == 'number' ? 0 : '')}',
      decoration: InputDecoration(labelText: label),
      keyboardType: field['type'] == 'number'
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.multiline,
      maxLines: field['type'] == 'number' ? 1 : 3,
      onChanged: (v) =>
          values[id] = field['type'] == 'number' ? num.tryParse(v) : v,
      validator: (v) {
        if (field['required'] == true && (v ?? '').trim().isEmpty) {
          return 'Campo richiesto';
        }
        if (field['type'] == 'number' &&
            (num.tryParse(v ?? '')?.isFinite != true)) {
          return 'Inserisci un numero';
        }
        return null;
      },
      onSaved: (v) =>
          values[id] = field['type'] == 'number' ? num.parse(v!) : v ?? '',
    );
  }
}
