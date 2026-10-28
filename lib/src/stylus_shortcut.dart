import 'package:flutter/material.dart';

import 'editing_tool.dart';

class StylusShortcut {
  final EditingTool tool;
  final Color color;
  final double width;
  const StylusShortcut(this.tool, this.color, this.width);

  static const preferenceKey = 'stylus_radial_shortcuts';
  static const holdDelayPreference = 'stylus_radial_hold_delay_ms';
  static const defaultHoldDelayMs = 1100;
  static const minHoldDelayMs = 300;
  static const maxHoldDelayMs = 2000;
  static const defaults = [
    StylusShortcut(EditingTool.STYLUS, Colors.black, 2.5),
    StylusShortcut(EditingTool.HIGHLIGHT, Color(0xFFFFF59D), 15),
    StylusShortcut(EditingTool.ERASER, Colors.grey, 10),
    StylusShortcut(EditingTool.SHAPE_AXES, Colors.black, 2.5),
    StylusShortcut(EditingTool.SHAPE_RECT, Colors.blue, 2.5),
  ];
  static List<EditingTool> get tools => [
    EditingTool.STYLUS,
    EditingTool.HIGHLIGHT,
    EditingTool.ERASER,
    EditingTool.SELECT,
    EditingTool.MOVE,
    ...EditingTool.values.where((t) => t.isShape),
  ];

  Map<String, Object> toJson() => {
    'tool': tool.name,
    'color': color.toARGB32(),
    'width': width,
  };
  static StylusShortcut fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Scorciatoia non valida');
    final tool = EditingTool.values.byName(value['tool'] as String);
    final width = (value['width'] as num).toDouble();
    if (!tools.contains(tool) || !width.isFinite || width < .1 || width > 30) {
      throw const FormatException('Scorciatoia non valida');
    }
    return StylusShortcut(tool, Color(value['color'] as int), width);
  }

  String get label => labelFor(tool);
  IconData get icon => iconFor(tool);
  static String labelFor(EditingTool tool) => switch (tool) {
    EditingTool.STYLUS => 'Penna',
    EditingTool.HIGHLIGHT => 'Evidenziatore',
    EditingTool.ERASER => 'Gomma',
    EditingTool.SELECT => 'Selezione',
    EditingTool.MOVE => 'Sposta',
    EditingTool.SHAPE_LINE => 'Linea',
    EditingTool.SHAPE_DASHED_LINE => 'Linea tratteggiata',
    EditingTool.SHAPE_RECT => 'Rettangolo',
    EditingTool.SHAPE_CIRCLE => 'Cerchio',
    EditingTool.SHAPE_SQUARE => 'Quadrato',
    EditingTool.SHAPE_CUBE => 'Cubo',
    EditingTool.SHAPE_CYLINDER => 'Cilindro',
    EditingTool.SHAPE_SPHERE => 'Sfera',
    EditingTool.SHAPE_AXES => 'Assi cartesiani',
    _ => tool.name,
  };
  static IconData iconFor(EditingTool tool) => switch (tool) {
    EditingTool.STYLUS => Icons.edit,
    EditingTool.HIGHLIGHT => Icons.highlight,
    EditingTool.ERASER => Icons.auto_fix_normal,
    EditingTool.SELECT => Icons.gesture,
    EditingTool.MOVE => Icons.pan_tool_outlined,
    EditingTool.SHAPE_AXES => Icons.add,
    EditingTool.SHAPE_CIRCLE => Icons.circle_outlined,
    EditingTool.SHAPE_LINE => Icons.horizontal_rule,
    EditingTool.SHAPE_DASHED_LINE => Icons.more_horiz,
    EditingTool.SHAPE_RECT => Icons.rectangle_outlined,
    EditingTool.SHAPE_SQUARE => Icons.check_box_outline_blank,
    EditingTool.SHAPE_CUBE => Icons.view_in_ar,
    EditingTool.SHAPE_CYLINDER => Icons.album_outlined,
    EditingTool.SHAPE_SPHERE => Icons.language,
    _ => Icons.category_outlined,
  };
}
