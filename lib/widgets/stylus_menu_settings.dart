import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/stylus_shortcut.dart';

import 'ink_options_panel.dart';

Future<void> showStylusMenuSettings(
  BuildContext context,
  ThemeController theme,
) async {
  var delay = theme.stylusMenuHoldDelayMs;
  final slots = await showStylusShortcutSettings(
    context,
    theme.stylusShortcuts,
    holdDelayMs: delay,
    onSaveDelay: (value) => delay = value,
  );
  if (slots != null) {
    await theme.setStylusMenuSettings(shortcuts: slots, holdDelayMs: delay);
  }
}

Future<List<StylusShortcut>?> showStylusShortcutSettings(
  BuildContext context,
  List<StylusShortcut> initial, {
  int? holdDelayMs,
  ValueChanged<int>? onSaveDelay,
}) {
  final slots = List<StylusShortcut>.of(initial);
  var delay = (holdDelayMs ?? StylusShortcut.defaultHoldDelayMs).clamp(
    StylusShortcut.minHoldDelayMs,
    StylusShortcut.maxHoldDelayMs,
  );
  return showDialog<List<StylusShortcut>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: Text(
          holdDelayMs == null
              ? 'Scorciatoie della penna'
              : 'Menù circolare della penna',
        ),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (holdDelayMs != null) ...[
                  const Text(
                    'Tieni premuta la penna, trascina su uno strumento e solleva per selezionarlo.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tempo di apertura: ${(delay / 1000).toStringAsFixed(1)} s',
                  ),
                  Slider(
                    key: const ValueKey('stylus-menu-hold-delay'),
                    value: delay.toDouble(),
                    min: StylusShortcut.minHoldDelayMs.toDouble(),
                    max: StylusShortcut.maxHoldDelayMs.toDouble(),
                    divisions: 17,
                    label: '${(delay / 1000).toStringAsFixed(1)} s',
                    onChanged: (value) => refresh(() => delay = value.round()),
                  ),
                  const Divider(),
                ],
                const Text('Incolla è sempre disponibile nel primo pulsante.'),
                for (var i = 0; i < slots.length; i++)
                  ListTile(
                    key: ValueKey('edit-radial-slot-$i'),
                    leading: Icon(slots[i].icon),
                    title: Text('${i + 1}. ${slots[i].label}'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final value = await _editShortcut(context, slots[i]);
                      if (value != null && context.mounted)
                        refresh(() => slots[i] = value);
                    },
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
          FilledButton(
            onPressed: () {
              onSaveDelay?.call(delay);
              Navigator.pop(context, slots);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ),
  );
}

Future<StylusShortcut?> _editShortcut(
  BuildContext context,
  StylusShortcut initial,
) {
  var tool = initial.tool;
  var color = initial.color;
  var width = initial.width;
  return showDialog<StylusShortcut>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        backgroundColor: const Color(0xFF424242),
        title: const Text('Configura scorciatoia'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<EditingTool>(
                  value: tool,
                  isExpanded: true,
                  items: [
                    for (final t in StylusShortcut.tools)
                      DropdownMenuItem(
                        value: t,
                        child: Text(StylusShortcut.labelFor(t)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) refresh(() => tool = value);
                  },
                ),
                if (tool == EditingTool.STYLUS ||
                    tool == EditingTool.HIGHLIGHT ||
                    tool.isShape) ...[
                  const SizedBox(height: 16),
                  InkColorSwatches(
                    colors: {
                      color,
                      Colors.black,
                      Colors.white,
                      Colors.grey,
                      Colors.red,
                      Colors.blue,
                      Colors.green,
                      Colors.purple,
                      Colors.orange,
                      const Color(0xFFFFF59D),
                      const Color(0xFFA5D6A7),
                      const Color(0xFF81D4FA),
                    }.toList(),
                    selected: color,
                    onSelected: (value) => refresh(() => color = value),
                  ),
                ],
                if (tool != EditingTool.SELECT && tool != EditingTool.MOVE) ...[
                  const SizedBox(height: 16),
                  Text('Spessore: ${(width * .3528).toStringAsFixed(2)} mm'),
                  Slider(
                    value: width,
                    min: .1,
                    max: 30,
                    onChanged: (value) => refresh(() => width = value),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, StylusShortcut(tool, color, width)),
            child: const Text('Conferma'),
          ),
        ],
      ),
    ),
  );
}
