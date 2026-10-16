import 'dart:typed_data';

import 'package:xournalpp/src/app_appearance.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/widgets/canvas_toolbar.dart';
import 'package:xournalpp/src/editing_tool.dart'; // EditingTool

/// Toolbar UNICA e globale (split-screen).
///
/// Legge il pannello con focus (`WorkspaceController.active`) e indirizza TUTTI
/// i comandi (strumento, colore, spessore, forme, gomma, PDF) a quel solo
/// `CanvasController`. Riusa il `CanvasToolbar` esistente per i pulsanti,
/// fornendogli via Provider il controller del pannello attivo.
class UnifiedToolbar extends StatefulWidget implements PreferredSizeWidget {
  final VoidCallback? onPomodoroTap;
  final bool pomodoroActive;
  final ValueNotifier<double>? pomodoroProgress;
  final VoidCallback? onOpenFile;
  final VoidCallback? onNavigationTap;
  final bool openingFile;

  /// Callback della WorkspacePage per aprire un PDF in una scheda separata:
  /// serve a far funzionare l'opzione "In una nuova scheda" del dialogo di
  /// import anche dalla toolbar unificata (la logica PDF resta invariata).
  final void Function(String pdfPath, String title, Uint8List pickedBytes)?
      onOpenPdfInNewTab;

  const UnifiedToolbar({
    super.key,
    this.onPomodoroTap,
    this.pomodoroActive = false,
    this.pomodoroProgress,
    this.onOpenFile,
    this.onNavigationTap,
    this.openingFile = false,
    this.onOpenPdfInNewTab,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<UnifiedToolbar> createState() => _UnifiedToolbarState();
}

class _UnifiedToolbarState extends State<UnifiedToolbar> {
  final GlobalKey _penKey = GlobalKey();
  final GlobalKey _hlKey = GlobalKey();
  final GlobalKey _shapeKey = GlobalKey();
  final GlobalKey _eraserKey = GlobalKey();

  static const List<Color> _penColors = [
    Colors.black,
    Colors.grey,
    Colors.white,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.orange,
  ];
  static const List<Color> _hlColors = [
    Color(0xFFFFF59D),
    Color(0xFFA5D6A7),
    Color(0xFF81D4FA),
    Color(0xFFF48FB1),
    Color(0xFFCE93D8),
    Color(0xFFFFCC80),
  ];

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final CanvasController ctrl = ws.active;

    // Forniamo al CanvasToolbar (che legge Provider<CanvasController>) il
    // controller del pannello ATTIVO: cambiando focus, la toolbar si riallinea.
    return ChangeNotifierProvider<CanvasController>.value(
      value: ctrl,
      child: CanvasToolbar(
        penKey: _penKey,
        highlighterKey: _hlKey,
        shapeKey: _shapeKey,
        eraserKey: _eraserKey,
        onPenTap: () => _openSettingsMenu(
          context,
          ctrl,
          _penKey,
          'Penna',
          _penColors,
          ctrl.penColor,
          ctrl.penWidth,
          ctrl.setPenProps,
        ),
        onHighlighterTap: () => _openSettingsMenu(
          context,
          ctrl,
          _hlKey,
          'Evidenziatore',
          _hlColors,
          ctrl.highlighterColor,
          ctrl.highlighterWidth,
          ctrl.setHighlighterProps,
        ),
        onShapeTap: () => _openShapeSettings(context, ctrl),
        onEraserTap: () => _openEraserSettings(context, ctrl),
        onImportPdf: () =>
            ctrl.importPdf(context, onOpenInNewTab: widget.onOpenPdfInNewTab),
        onPomodoroTap: widget.onPomodoroTap ?? () {},
        pomodoroActive: widget.pomodoroActive,
        pomodoroProgress: widget.pomodoroProgress,
        onOpenFile: widget.onOpenFile,
        onNavigationTap: widget.onNavigationTap,
        openingFile: widget.openingFile,
        onToolSelect: (tool) => ctrl.setTool(tool), // -> pannello attivo
      ),
    );
  }

  // ----- pannello opaco Pomodoro ancorato sotto il pulsante -----
  void _showPanel(BuildContext context, GlobalKey anchor, Widget child) {
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final double left = math.max(
      16.0,
      math.min(
        pos.dx - 160 + box.size.width / 2,
        MediaQuery.of(context).size.width - 336,
      ),
    );

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            top: pos.dy + box.size.height + 8,
            left: left,
            child: ClipPath(
              clipper: const ShapeBorderClipper(
                shape: AppAppearance.panelShape,
              ),
              child: Material(
                color: AppAppearance.panel,
                shape: AppAppearance.panelShape,
                elevation: 0,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettingsMenu(
    BuildContext context,
    CanvasController ctrl,
    GlobalKey key,
    String title,
    List<Color> colors,
    Color curC,
    double curW,
    Function(Color?, double?) onUpdate,
  ) {
    _showPanel(
      context,
      key,
      StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors
                  .map(
                    (c) => InkWell(
                      onTap: () {
                        onUpdate(c, null);
                        setDialogState(() => curC = c);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: curC == c ? Colors.black : Colors.black12,
                            width: curC == c ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Spessore: ${(curW * 0.3528).toStringAsFixed(2)} mm',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Slider(
              value: curW,
              min: title == 'Penna' ? 0.1 : 0.5,
              max: 30.0,
              onChanged: (val) {
                onUpdate(null, val);
                setDialogState(() => curW = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openShapeSettings(BuildContext context, CanvasController ctrl) {
    _showPanel(
      context,
      _shapeKey,
      StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Strumento Forma:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _shapeItem(
              context,
              'Linea',
              Icons.horizontal_rule,
              EditingTool.SHAPE_LINE,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Linea tratteggiata',
              Icons.more_horiz,
              EditingTool.SHAPE_DASHED_LINE,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Rettangolo',
              Icons.rectangle_outlined,
              EditingTool.SHAPE_RECT,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Cerchio',
              Icons.circle_outlined,
              EditingTool.SHAPE_CIRCLE,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Quadrato',
              Icons.check_box_outline_blank,
              EditingTool.SHAPE_SQUARE,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Cubo',
              Icons.view_in_ar,
              EditingTool.SHAPE_CUBE,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Cilindro',
              Icons.album,
              EditingTool.SHAPE_CYLINDER,
              ctrl,
              setDialogState,
            ),
            _shapeItem(
              context,
              'Sfera',
              Icons.lens,
              EditingTool.SHAPE_SPHERE,
              ctrl,
              setDialogState,
            ),
            const Divider(),
            const Text(
              'Proprietà figure:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  const [
                        Colors.black,
                        Colors.grey,
                        Colors.red,
                        Colors.blue,
                        Colors.green,
                      ]
                      .map(
                        (c) => InkWell(
                          onTap: () {
                            ctrl.setShapeProps(c, null);
                            setDialogState(() {});
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: ctrl.shapeColor == c
                                    ? Colors.black
                                    : Colors.black12,
                                width: ctrl.shapeColor == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
            Slider(
              value: ctrl.shapeWidth,
              min: 0.5,
              max: 20.0,
              onChanged: (val) {
                ctrl.setShapeProps(null, val);
                setDialogState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _shapeItem(
    BuildContext context,
    String title,
    IconData icon,
    EditingTool tool,
    CanvasController ctrl,
    StateSetter setDialogState,
  ) {
    final bool isSelected = ctrl.toolData[PointerDeviceKind.stylus] == tool;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      onTap: () {
        ctrl.setTool(tool);
        setDialogState(() {});
      },
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  void _openEraserSettings(BuildContext context, CanvasController ctrl) {
    _showPanel(
      context,
      _eraserKey,
      StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Modalità Gomma:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            RadioListTile<EraserMode>(
              title: const Text('Pixel per Pixel'),
              value: EraserMode.pixel,
              groupValue: ctrl.eraserMode,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                if (val != null) {
                  ctrl.setEraserProps(val, null);
                  setDialogState(() {});
                }
              },
            ),
            RadioListTile<EraserMode>(
              title: const Text('Intero Tratto'),
              value: EraserMode.stroke,
              groupValue: ctrl.eraserMode,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                if (val != null) {
                  ctrl.setEraserProps(val, null);
                  setDialogState(() {});
                }
              },
            ),
            const Divider(),
            Text(
              'Grandezza Gomma: ${(ctrl.eraserWidth * 0.3528).toStringAsFixed(2)} mm',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Slider(
              value: ctrl.eraserWidth,
              min: 2.0,
              max: 40.0,
              onChanged: (val) {
                ctrl.setEraserProps(null, val);
                setDialogState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}
