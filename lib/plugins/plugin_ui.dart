import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'plugin_latex.dart';
import 'plugin_manifest.dart';
import 'plugin_services.dart';

PluginHost pluginUiHost(BuildContext context) => PluginHost(
  latex: renderPluginLatex,
  openFile: (args) async {
    if (!context.mounted) throw StateError('Interfaccia chiusa');
    try {
      final file = await FilePickerCross.importFromStorage(
        type: args['type'] == 'image' ? FileTypeCross.image : FileTypeCross.any,
      );
      final bytes = file.toUint8List();
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('File: massimo 8 MiB');
      }
      return {
        'name': file.fileName ?? 'file',
        'base64': base64Encode(bytes),
        if (args['encoding'] == 'utf8') 'text': utf8.decode(bytes),
      };
    } catch (error) {
      if (error == 'No file selected.') return null;
      rethrow;
    }
  },
  form: (args) async {
    if (!context.mounted) throw StateError('Interfaccia chiusa');
    // Reuse the manifest's input validation before building an untrusted form.
    NotePlugin.parse(
      jsonEncode({
        'apiVersion': 1,
        'id': 'host.form',
        'name': 'Form',
        'version': '1',
        'permissions': [],
        'commands': [
          {
            'id': 'form',
            'label': 'Form',
            'inputs': args['fields'],
            'steps': [],
          },
        ],
      }),
    );
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DynamicPluginForm(args),
    );
  },
  preview: (args) async {
    if (!context.mounted) throw StateError('Interfaccia chiusa');
    final text = args['text'] as String? ?? '';
    if (text.length > 65536) throw StateError('Anteprima troppo lunga');
    final child = switch (args['type']) {
      'latex' => Math.tex(text, textStyle: const TextStyle(fontSize: 24)),
      'image' => Image.memory(pluginBytes(args)),
      _ => SelectableText(text),
    };
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(args['title'] as String? ?? 'Anteprima'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: child),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
  },
);

class _DynamicPluginForm extends StatefulWidget {
  final Map<String, dynamic> args;
  const _DynamicPluginForm(this.args);
  @override
  State<_DynamicPluginForm> createState() => _DynamicPluginFormState();
}

class _DynamicPluginFormState extends State<_DynamicPluginForm> {
  final key = GlobalKey<FormState>();
  final values = <String, dynamic>{};
  @override
  void initState() {
    super.initState();
    for (final f in widget.args['fields'] as List) {
      values[f['id'] as String] =
          f['default'] ??
          (f['type'] == 'boolean'
              ? false
              : f['type'] == 'choice'
              ? (f['options'] as List).first
              : null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.args['title'] as String? ?? 'Plugin'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in widget.args['fields'] as List)
                if (field['type'] == 'boolean')
                  SwitchListTile(
                    title: Text(field['label'] as String),
                    value: values[field['id']] == true,
                    onChanged: (v) =>
                        setState(() => values[field['id'] as String] = v),
                  )
                else if (field['type'] == 'choice')
                  DropdownButtonFormField<String>(
                    initialValue: values[field['id']] as String?,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: field['label'] as String,
                    ),
                    items: [
                      for (final option in field['options'] as List)
                        DropdownMenuItem(
                          value: option as String,
                          child: Text(option),
                        ),
                    ],
                    onChanged: (v) => values[field['id'] as String] = v,
                  )
                else
                  TextFormField(
                    initialValue: '${values[field['id']] ?? ''}',
                    maxLength: 65536,
                    minLines: field['multiline'] == true ? 3 : 1,
                    maxLines: field['multiline'] == true ? 8 : 1,
                    decoration: InputDecoration(
                      labelText: field['label'] as String,
                      counterText: '',
                    ),
                    keyboardType: field['type'] == 'number'
                        ? const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          )
                        : TextInputType.multiline,
                    onChanged: (v) => values[field['id'] as String] =
                        field['type'] == 'number' ? num.tryParse(v) : v,
                    validator: (v) {
                      if (field['required'] == true &&
                          (v == null || v.trim().isEmpty)) {
                        return 'Campo obbligatorio';
                      }
                      if (field['type'] == 'number' &&
                          (num.tryParse(v ?? '')?.isFinite != true)) {
                        return 'Numero non valido';
                      }
                      return null;
                    },
                  ),
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
          if (key.currentState!.validate()) Navigator.pop(context, values);
        },
        child: Text(widget.args['submitLabel'] as String? ?? 'Continua'),
      ),
    ],
  );
}
