import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:xournalpp/src/stylus_shortcut.dart';
import 'package:xournalpp/src/editing_tool.dart';

Future<void> showShapeOptionsPanel(
  BuildContext context,
  CanvasController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, refresh) => AlertDialog(
      backgroundColor: const Color(0xFF424242),
      title: const Text('Figure'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tool in StylusShortcut.tools.where(
                    (t) => t.isShape,
                  ))
                    ChoiceChip(
                      label: Text(StylusShortcut.labelFor(tool)),
                      selected:
                          controller.toolData[PointerDeviceKind.stylus] == tool,
                      onSelected: (_) {
                        controller.setTool(tool);
                        refresh(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              InkColorSwatches(
                colors: const [
                  Colors.black,
                  Colors.grey,
                  Colors.white,
                  Colors.red,
                  Colors.blue,
                  Colors.green,
                  Colors.purple,
                  Colors.orange,
                ],
                selected: controller.shapeColor,
                onSelected: (color) {
                  controller.setShapeProps(color, null);
                  refresh(() {});
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Spessore: ${(controller.shapeWidth * .3528).toStringAsFixed(2)} mm',
              ),
              Slider(
                value: controller.shapeWidth.clamp(.5, 30),
                min: .5,
                max: 30,
                onChanged: (width) {
                  controller.setShapeProps(null, width);
                  refresh(() {});
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  ),
);

Future<void> showInkOptionsPanel(
  BuildContext context,
  CanvasController controller,
  GlobalKey anchor,
  String title,
  List<Color> colors,
  Color color,
  double width,
  void Function(Color?, double?) update,
) async {
  final box = anchor.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  final screen = MediaQuery.sizeOf(context);
  final panelWidth = math.min(320.0, screen.width - 32);
  final position = box.localToGlobal(Offset.zero);
  final left = (position.dx + box.size.width / 2 - panelWidth / 2).clamp(
    16.0,
    screen.width - panelWidth - 16,
  );
  final top = math.min(position.dy + box.size.height + 8, screen.height / 2);
  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: panelWidth,
          child: Material(
            key: const ValueKey('ink-options-panel'),
            color: const Color(0xFF424242),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  brightness: Brightness.dark,
                  onSurface: Colors.white,
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: screen.height - top - 16,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, refresh) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        InkColorSwatches(
                          colors: colors,
                          selected: color,
                          onSelected: (value) {
                            update(value, null);
                            refresh(() => color = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Spessore: ${(width * .3528).toStringAsFixed(2)} mm',
                        ),
                        Slider(
                          value: width.clamp(title == 'Penna' ? .1 : .5, 30),
                          min: title == 'Penna' ? .1 : .5,
                          max: 30,
                          onChanged: (value) {
                            update(null, value);
                            refresh(() => width = value);
                          },
                        ),
                        if (title == 'Penna')
                          SwitchListTile(
                            key: const ValueKey('pen-pressure-toggle'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Spessore con la pressione'),
                            subtitle: const Text(
                              'Disattiva per un tratto uniforme',
                            ),
                            value: controller.penPressureEnabled,
                            onChanged: (value) {
                              controller.setPenPressureEnabled(value);
                              refresh(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class InkColorSwatches extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;
  const InkColorSwatches({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final color in colors)
        Semantics(
          button: true,
          selected: selected.toARGB32() == color.toARGB32(),
          label: 'Colore ${color.toARGB32().toRadixString(16)}',
          child: InkWell(
            onTap: () => onSelected(color),
            customBorder: const CircleBorder(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white70,
                  width: selected.toARGB32() == color.toARGB32() ? 2 : 1,
                ),
              ),
              child: selected.toARGB32() == color.toARGB32()
                  ? Icon(
                      Icons.check,
                      size: 19,
                      color: color.computeLuminance() > .4
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
          ),
        ),
    ],
  );
}
