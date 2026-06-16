import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/widgets/canvas_toolbar.dart';

class StylusGestureRecognizer extends OneSequenceGestureRecognizer {
  bool blockStylusPan;
  StylusGestureRecognizer({required this.blockStylusPan});

  @override
  String get debugDescription => 'stylus_interceptor';

  @override
  void addPointer(PointerDownEvent event) {
    if (blockStylusPan && (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus)) {
      startTrackingPointer(event.pointer);
      resolve(GestureDisposition.accepted); 
    } else {
      stopTrackingPointer(event.pointer); 
    }
  }

  @override
  void handleEvent(PointerEvent event) {}
  @override
  void didStopTrackingLastPointer(int pointer) {}
}

class CanvasPage extends StatefulWidget {
  final XppFile? file;
  final String? filePath;
  const CanvasPage({Key? key, this.file, this.filePath}) : super(key: key);
  @override
  CanvasPageState createState() => CanvasPageState(); 
}

class CanvasPageState extends State<CanvasPage> {
  late CanvasController _controller;
  final TransformationController _zoomController = TransformationController();
  final GlobalKey<ZoomableWidgetState> _zoomableKey = GlobalKey();
  
  final GlobalKey _penBtn = GlobalKey(), _highlighterBtn = GlobalKey(), _eraserBtn = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = CanvasController()..init(widget.file);
  }

  Future<bool> promptSaveIfUnsaved() async {
    if (!_controller.hasUnsavedChanges) return true; 
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifiche non salvate'),
        content: const Text('Vuoi salvare il documento prima di chiudere? Le modifiche andranno perse.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Chiudi senza salvare', style: TextStyle(color: Colors.red))),
          ElevatedButton(onPressed: () async { await _controller.saveFile(context); Navigator.pop(context, true); }, child: const Text('Salva')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<CanvasController>(
        builder: (context, ctrl, child) {
          final isDarkMode = Theme.of(context).brightness == Brightness.dark;

          return Scaffold(
            backgroundColor: isDarkMode ? Colors.black : Theme.of(context).colorScheme.surfaceContainerHighest,
            appBar: CanvasToolbar(
              penKey: _penBtn, highlighterKey: _highlighterBtn, eraserKey: _eraserBtn,
              onPenTap: () => _openSettingsMenu(context, ctrl, _penBtn, 'Penna', [Colors.black, Colors.grey, Colors.white, Colors.red, Colors.blue, Colors.green, Colors.purple, Colors.orange], ctrl.penColor, ctrl.penWidth, ctrl.setPenProps),
              onHighlighterTap: () => _openSettingsMenu(context, ctrl, _highlighterBtn, 'Evidenziatore', [const Color(0xFFFFF59D), const Color(0xFFA5D6A7), const Color(0xFF81D4FA), const Color(0xFFF48FB1), const Color(0xFFCE93D8), const Color(0xFFFFCC80)], ctrl.highlighterColor, ctrl.highlighterWidth, ctrl.setHighlighterProps),
              onEraserTap: () => _openEraserSettings(context, ctrl),
            ),
            drawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [ Icon(Icons.book, size: 48, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 8), Text(ctrl.file?.title ?? 'Documento', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)) ])),
                  ListTile(leading: const Icon(Icons.home), title: const Text('Torna alla Home'), onTap: () async { Navigator.of(context).pop(); if (await promptSaveIfUnsaved()) Navigator.of(context).pop(); }),
                  const Divider(),
                  ListTile(leading: const Icon(Icons.save), title: const Text('Salva (.xopp)'), onTap: () { Navigator.pop(context); ctrl.saveFile(context); }),
                  ListTile(leading: const Icon(Icons.picture_as_pdf), title: const Text('Esporta in PDF'), onTap: () { Navigator.pop(context); ctrl.exportToPdf(context); }),
                ],
              ),
            ),
            body: ZoomableWidget(
              key: _zoomableKey,
              controller: _zoomController,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse}),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), 
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(
                    children: List.generate(ctrl.file?.pages?.length ?? 0, (pageIndex) {
                      ctrl.pageStackKeys.putIfAbsent(pageIndex, () => GlobalKey<XppPageStackState>());

                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]),
                        child: Card(
                          elevation: 0, margin: EdgeInsets.zero, color: Colors.white,
                          child: AspectRatio(
                            aspectRatio: ctrl.file!.pages![pageIndex].pageSize!.ratio,
                            child: FittedBox(
                              child: RawGestureDetector(
                                gestures: <Type, GestureRecognizerFactory>{
                                  StylusGestureRecognizer: GestureRecognizerFactoryWithHandlers<StylusGestureRecognizer>(
                                    () => StylusGestureRecognizer(blockStylusPan: !ctrl.isPanEnabled),
                                    (instance) => instance.blockStylusPan = !ctrl.isPanEnabled,
                                  ),
                                },
                                child: Listener(
                                  onPointerUp: (_) => ctrl.eraserSnapshotTaken = false,
                                  child: PointerListener(
                                    translationMatrix: _zoomController.value,
                                    toolData: ctrl.toolData,
                                    strokeWidth: ctrl.getCurrentToolWidth(), 
                                    color: ctrl.getCurrentToolColor(),       
                                    shapeRecognition: ctrl.shapeRecognition,
                                    buttonDownAction: ctrl.buttonDownAction,
                                    buttonUpAction: ctrl.buttonUpAction,
                                    
                                    onToolChanged: (tool) { ctrl.setTool(tool); _zoomableKey.currentState?.setState(() => _zoomableKey.currentState!.enabled = true); },
                                    getPageContent: () => ctrl.file!.pages![pageIndex].layers![0].content ?? [],
                                    onDeviceChange: ({int? device, PointerDeviceKind? kind}) {}, 
                                    
                                    onDeleteContent: (deleted) => ctrl.deleteContent(pageIndex, deleted),
                                    onContentChanged: () => ctrl.pageStackKeys[pageIndex]!.currentState!.setPageData(ctrl.file!.pages![pageIndex]),
                                    removeLastContent: () => ctrl.removeLastContent(pageIndex),
                                    filterEraser: ({Offset? coordinates, double? radius}) => ctrl.filterEraser(pageIndex: pageIndex, coordinates: coordinates, radius: radius),
                                    onNewContent: (newContent) => ctrl.addNewContent(pageIndex, newContent),
                                    
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: XppPageStack(key: ctrl.pageStackKeys[pageIndex], page: ctrl.file!.pages![pageIndex]),
                                    ),
                                  ), 
                                ), 
                              ),
                            ), 
                          ), 
                        ),
                      );
                    }),
                  ),
                ),
              ), 
            ), 
          );
        },
      ),
    );
  }

  void _openEraserSettings(BuildContext context, CanvasController ctrl) {
    final renderBox = _eraserBtn.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    double leftPosition = max(16, min(renderBox.localToGlobal(Offset.zero).dx - 160 + (renderBox.size.width / 2), MediaQuery.of(context).size.width - 336));

    showDialog(context: context, barrierColor: Colors.transparent, builder: (context) => Stack(children: [
      Positioned(top: renderBox.localToGlobal(Offset.zero).dy + renderBox.size.height + 8, left: leftPosition, child: Material(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16), elevation: 6, child: Container(width: 320, padding: const EdgeInsets.all(16), child: StatefulBuilder(builder: (context, setDialogState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Modalità Gomma:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        RadioListTile<EraserMode>(title: const Text('Pixel per Pixel'), value: EraserMode.pixel, groupValue: ctrl.eraserMode, contentPadding: EdgeInsets.zero, onChanged: (val) { if (val != null) { ctrl.setEraserProps(val, null); setDialogState(() {}); } }),
        RadioListTile<EraserMode>(title: const Text('Intero Tratto'), value: EraserMode.stroke, groupValue: ctrl.eraserMode, contentPadding: EdgeInsets.zero, onChanged: (val) { if (val != null) { ctrl.setEraserProps(val, null); setDialogState(() {}); } }),
        const Divider(), const Text('Grandezza Gomma:', style: TextStyle(fontWeight: FontWeight.bold)),
        Slider(value: ctrl.eraserWidth, min: 2.0, max: 40.0, onChanged: (val) { ctrl.setEraserProps(null, val); setDialogState(() {}); })
      ])))))
    ]));
  }

  void _openSettingsMenu(BuildContext context, CanvasController ctrl, GlobalKey key, String title, List<Color> colors, Color curC, double curW, Function(Color?, double?) onUpdate) {
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    double leftPosition = max(16, min(renderBox.localToGlobal(Offset.zero).dx - 160 + (renderBox.size.width / 2), MediaQuery.of(context).size.width - 336));

    showDialog(context: context, barrierColor: Colors.transparent, builder: (context) => Stack(children: [
      Positioned(top: renderBox.localToGlobal(Offset.zero).dy + renderBox.size.height + 8, left: leftPosition, child: Material(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16), elevation: 6, child: Container(width: 320, padding: const EdgeInsets.all(16), child: StatefulBuilder(builder: (context, setDialogState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: colors.map((c) => InkWell(onTap: () { onUpdate(c, null); setDialogState(() => curC = c); }, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: curC == c ? Colors.black : Colors.black12, width: curC == c ? 3 : 1))))).toList()),
        const SizedBox(height: 24), const Text('Spessore:', style: TextStyle(fontWeight: FontWeight.bold)),
        Slider(value: curW, min: 0.5, max: 30.0, onChanged: (val) { onUpdate(null, val); setDialogState(() => curW = val); })
      ])))))
    ]));
  }
}