import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/ToolSettingsMenu.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:vector_math/vector_math_64.dart' show Vector4;
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

class CanvasPage extends StatefulWidget {
  CanvasPage({Key? key, this.file, this.filePath}) : super(key: key);

  @required
  final XppFile? file;
  final String? filePath;

  @override
  CanvasPageState createState() => CanvasPageState(); 
}

class CanvasPageState extends State<CanvasPage> with TickerProviderStateMixin {
  XppFile? _file;
  int currentPage = 0;
  Color toolColor = Colors.black;
  double toolWidth = 2.5;

  TransformationController _zoomController = TransformationController();
  Map<PointerDeviceKind?, EditingTool> _toolData = {};
  PointerDeviceKind? _currentDevice = PointerDeviceKind.touch;

  final GlobalKey<XppPageStackState> _pageStackKey = GlobalKey();
  final GlobalKey<PointerListenerState> _pointerListenerKey = GlobalKey();
  final GlobalKey<ZoomableWidgetState> _zoomableKey = GlobalKey();
  
  final GlobalKey _penButtonKey = GlobalKey();
  final GlobalKey _highlighterButtonKey = GlobalKey();

  double pageScale = 1;
  bool savingFile = false;
  bool shapeRecognition = false;
  
  bool hasUnsavedChanges = false;
  
  String buttonDownAction = 'eraser';
  String buttonUpAction = 'select';

  Animation<Matrix4>? _animationReset;
  late AnimationController _controllerReset;

  @override
  void initState() {
    _setMetadata();
    super.initState();
    _controllerReset = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    
    _toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
    _toolData[PointerDeviceKind.touch] = EditingTool.MOVE;

    SharedPreferences.getInstance().then((prefs) {
      final enabled = prefs.getBool(PreferencesKeys.kShapeRecognition);
      if (enabled != null) setState(() => shapeRecognition = enabled);

      final bDown = prefs.getString('buttonDownAction') ?? prefs.getString('stylusButtonAction'); 
      final bUp = prefs.getString('buttonUpAction');
      
      setState(() {
        if (bDown != null) buttonDownAction = bDown;
        if (bUp != null) buttonUpAction = bUp;
      });
    }).catchError((e) {});
  }

  Future<bool> promptSaveIfUnsaved() async {
    if (!hasUnsavedChanges) return true; 

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Modifiche non salvate', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Vuoi salvare il documento prima di chiudere la scheda? Le modifiche andranno perse.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text('Chiudi senza salvare', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              await saveFile(); 
              Navigator.pop(context, true); 
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: Text('Salva file'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _setTool(EditingTool newTool) {
    setState(() {
      _toolData[_currentDevice] = newTool;
      _toolData[PointerDeviceKind.stylus] = newTool; 
      _setZoomableState();
    });
  }

  void _openToolSettings(GlobalKey key) {
    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenWidth = MediaQuery.of(context).size.width;

    double menuWidth = 320.0;
    double leftPosition = offset.dx - (menuWidth / 2) + (size.width / 2); 
    if (leftPosition + menuWidth > screenWidth) leftPosition = screenWidth - menuWidth - 16; 
    if (leftPosition < 16) leftPosition = 16;

    showDialog(
      context: context,
      barrierColor: Colors.transparent, 
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: offset.dy + size.height + 8, 
              left: leftPosition,
              child: Material(
                color: Colors.transparent,
                child: ToolSettingsMenu(
                  initialColor: toolColor,
                  initialThickness: toolWidth,
                  onColorSelected: (color) {
                    setState(() => toolColor = color);
                  },
                  onThicknessChanged: (thickness) {
                    setState(() => toolWidth = thickness);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Capiamo se il sistema è in modalità scura
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Se è Dark Mode usa il nero assoluto, altrimenti il grigio chiaro adattivo
      backgroundColor: isDarkMode 
          ? Colors.black // <-- Puoi usare anche Color(0xFF121212) se preferisci un grigio scurissimo
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.book, size: 48, color: Theme.of(context).colorScheme.primary),
                  SizedBox(height: 8),
                  Text(_file?.title ?? 'Documento', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.home),
              title: Text('Torna alla Home'),
              onTap: () async {
                Navigator.of(context).pop(); 
                final canClose = await promptSaveIfUnsaved();
                if (canClose) {
                  Navigator.of(context).pop(); 
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.save),
              title: Text('Salva (.xopp)'),
              onTap: () {
                Navigator.pop(context);
                saveFile();
              },
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf),
              title: Text('Esporta in PDF'),
              onTap: () {
                Navigator.pop(context);
                exportToPdf();
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.edit_attributes),
              title: Text('Impostazioni Penna'),
              onTap: () {
                Navigator.pop(context);
                _showPenSettingsDialog();
              },
            ),
            ListTile(
              leading: Icon(Icons.wallpaper),
              title: Text('Cambia Sfondo'),
              onTap: () {
                Navigator.pop(context);
                _changeBackground();
              },
            ),
          ],
        ),
      ),
      
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        elevation: 1,
        shadowColor: Colors.black12,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Builder(
                builder: (context) => IconButton(
                  icon: Icon(Icons.menu), 
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              IconButton(icon: Icon(Icons.undo), onPressed: () {}), 
              IconButton(icon: Icon(Icons.redo), onPressed: () {}), 
              
              SizedBox(height: 30, child: VerticalDivider(width: 20)),
              
              // 2. NUOVE ICONE DELLA TOOLBAR!
              IconButton(
                key: _penButtonKey,
                icon: Icon(Icons.edit), 
                tooltip: 'Penna',
                color: _toolData[PointerDeviceKind.stylus] == EditingTool.STYLUS 
                    ? Theme.of(context).colorScheme.primary 
                    : null,
                onPressed: () {
                  if (_toolData[PointerDeviceKind.stylus] == EditingTool.STYLUS) {
                    _openToolSettings(_penButtonKey);
                  } else {
                    _setTool(EditingTool.STYLUS);
                  }
                },
              ),

              IconButton(
                key: _highlighterButtonKey,
                icon: Icon(Icons.highlight), // <--- Icona Evidenziatore nuova
                tooltip: 'Evidenziatore',
                color: _toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT 
                    ? Theme.of(context).colorScheme.primary 
                    : null,
                onPressed: () {
                  if (_toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT) {
                    _openToolSettings(_highlighterButtonKey);
                  } else {
                    _setTool(EditingTool.HIGHLIGHT);
                  }
                },
              ),

              IconButton(
                // Usa FaIcon invece del classico Icon
                icon: FaIcon(FontAwesomeIcons.eraser), 
                tooltip: 'Gomma',
                color: _toolData[PointerDeviceKind.stylus] == EditingTool.ERASER 
                    ? Theme.of(context).colorScheme.primary 
                    : null,
                onPressed: () => _setTool(EditingTool.ERASER),
              ),

              IconButton(
                icon: Icon(Icons.all_out), // <--- Icona Lazzo (Selezione espansa)
                tooltip: 'Lazo',
                color: _toolData[PointerDeviceKind.stylus] == EditingTool.SELECT 
                    ? Theme.of(context).colorScheme.primary 
                    : null,
                onPressed: () => _setTool(EditingTool.SELECT),
              ),

              IconButton(
                icon: Icon(Icons.open_with), // <--- Icona Mano/Spostamento (Frecce a 4 punte)
                tooltip: 'Sposta Pagina',
                color: _toolData[PointerDeviceKind.stylus] == EditingTool.MOVE 
                    ? Theme.of(context).colorScheme.primary 
                    : null,
                onPressed: () => _setTool(EditingTool.MOVE),
              ),
              
              SizedBox(height: 30, child: VerticalDivider(width: 20)),
              
              IconButton(
                icon: Icon(Icons.zoom_out),
                tooltip: 'Riduci Zoom',
                onPressed: () => _setScale(pageScale - 0.2),
              ),
              Container(
                width: 50,
                alignment: Alignment.center,
                child: Text('${(pageScale * 100).round()}%', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700)
                ),
              ),
              IconButton(
                icon: Icon(Icons.zoom_in),
                tooltip: 'Aumenta Zoom',
                onPressed: () => _setScale(pageScale + 0.2),
              ),

              SizedBox(height: 30, child: VerticalDivider(width: 20)),

              IconButton(
                icon: Icon(Icons.chevron_left), 
                tooltip: 'Pagina Precedente',
                onPressed: currentPage > 0 ? () {
                  setState(() {
                    currentPage--;
                    _pageStackKey.currentState!.setPageData(_file!.pages![currentPage]);
                  });
                } : null,
              ),
              
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  // Usa il colore "contenitore secondario" del tema di sistema
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Text(
                  'Pag. ${currentPage + 1} / ${_file!.pages!.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 13,
                    // Usa il colore del testo corretto per il contenitore secondario
                    color: Theme.of(context).colorScheme.onSecondaryContainer 
                  ),
                ),
              ),
              
              IconButton(
                icon: Icon(Icons.chevron_right), 
                tooltip: 'Pagina Successiva',
                onPressed: currentPage < _file!.pages!.length - 1 ? () {
                  setState(() {
                    currentPage++;
                    _pageStackKey.currentState!.setPageData(_file!.pages![currentPage]);
                  });
                } : null,
              ),
              
              IconButton(
                icon: Icon(Icons.note_add), 
                color: Theme.of(context).colorScheme.primary,
                tooltip: 'Aggiungi Pagina Sotto',
                onPressed: () {
                  setState(() {
                    hasUnsavedChanges = true; 
                    currentPage++;
                    XppPage newPage = XppPage.empty(background: Colors.white);
                    newPage.pageSize = _file!.pages![currentPage - 1].pageSize ?? XppPageSize.a4;
                    if (newPage.background != null) {
                       newPage.background!.size = newPage.pageSize;
                    }
                    _file!.pages!.insert(currentPage, newPage);
                    _pageStackKey.currentState!.setPageData(_file!.pages![currentPage]);
                  });
                }
              ),

              SizedBox(width: 16),

              if (savingFile) 
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12), 
                  child: SizedBox(
                    width: 20, height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2)
                  )
                ),
            ],
          ),
        ),
      ),
      
      body: Stack(fit: StackFit.expand, children: [
        Hero(
          tag: 'ZoomArea',
          child: ZoomableWidget(
              key: _zoomableKey,
              controller: _zoomController,
              onInteractionStart: _onInteractionStart,
              onInteractionUpdate: (details) {
                setState(() => pageScale = _zoomController.value.entry(0, 0));
              },
              child: Center(
                child: Card(
                  elevation: 6,
                  color: Colors.white,
                  margin: EdgeInsets.all(16),
                  child: AspectRatio(
                    aspectRatio: _file!.pages![currentPage].pageSize!.ratio,
                    child: FittedBox(
                      child: PointerListener(
                        key: _pointerListenerKey,
                        translationMatrix: _zoomController.value,
                        toolData: _toolData,
                        strokeWidth: toolWidth,
                        color: toolColor,
                        shapeRecognition: shapeRecognition,
                        buttonDownAction: buttonDownAction,
                        buttonUpAction: buttonUpAction,
                        getPageContent: () => _file!.pages![currentPage].layers![0].content ?? [],
                        onDeleteContent: (deleted) {
                          setState(() {
                            hasUnsavedChanges = true; 
                            _file!.pages![currentPage].layers![0].content!.removeWhere((element) => deleted.contains(element));
                          });
                          _pageStackKey.currentState!.setPageData(_file!.pages![currentPage]);
                        },
                        onContentChanged: () {
                          _pageStackKey.currentState!.setPageData(_file!.pages![currentPage]);
                        },
                        onDeviceChange: ({int? device, PointerDeviceKind? kind}) {
                          setDefaultDeviceIfNotSet(kind: kind);
                          _currentDevice = kind;
                          _setZoomableState();
                        },
                        removeLastContent: () {
                          hasUnsavedChanges = true; 
                          _file!.pages![currentPage].layers![0].content!.removeLast();
                        },
                        filterEraser: ({Offset? coordinates, double? radius}) {
                          List<Function> removalFunctions = [];
                          _file!.pages![currentPage].layers![0].content!.forEach((stroke) {
                            final delta = stroke!.eraseWhere(coordinates: coordinates, radius: radius);
                            if (!delta.affected) return;
                            removalFunctions.add(() {
                              final int index = _file!.pages![currentPage].layers![0].content!.indexOf(stroke);
                              _file!.pages![currentPage].layers![0].content!.removeAt(index);
                              _file!.pages![currentPage].layers![0].content!.insertAll(index, delta.newContent);
                            });
                          });
                          if (removalFunctions.isNotEmpty) {
                            hasUnsavedChanges = true; 
                            removalFunctions.forEach((element) { element(); });
                            setState(() {});
                          }
                        },
                        onNewContent: (newContent) {
                          hasUnsavedChanges = true; 
                          _file!.pages![currentPage].layers![0].content =
                              new List.from(_file!.pages![currentPage].layers![0].content!)..add(newContent);
                          _pageStackKey.currentState!.setPageData(_file!.pages![currentPage]);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: XppPageStack(
                            key: _pageStackKey,
                            page: _file!.pages![currentPage],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )),
        ),
      ]),
    );
  }

  void _setMetadata() { _file = widget.file; }

  void _changeBackground() {
    showModalBottomSheet(
      elevation: 16,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
      context: context,
      builder: (context) => ToolBoxBottomSheet(
        onBackgroundChange: (newBackground) {
          newBackground.size = _file!.pages![currentPage].pageSize;
          setState(() {
            hasUnsavedChanges = true; 
            _file!.pages![currentPage].background = newBackground;
          });
        },
      )
    );
  }

  Future<void> _showTitleDialog() async {
    await showDialog(
        context: context,
        builder: (context) {
          TextEditingController titleController = TextEditingController(text: _file!.title);
          return AlertDialog(
            title: Text("Rinomina Documento"),
            content: TextField(
                autofocus: true,
                controller: titleController,
                decoration: InputDecoration(border: OutlineInputBorder(), labelText: "Nuovo Titolo")),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Annulla")),
              TextButton(
                onPressed: () {
                  setState(() { 
                    _file!.title = titleController.text;
                    hasUnsavedChanges = true; 
                  });
                  Navigator.of(context).pop();
                },
                child: Text("Salva"),
              ),
            ],
          );
        });
  }

  void setDefaultDeviceIfNotSet({PointerDeviceKind? kind}) {
    if (!_toolData.keys.contains(kind)) {
      EditingTool tool;
      switch (kind) {
        case PointerDeviceKind.touch: tool = EditingTool.MOVE; break;
        case PointerDeviceKind.invertedStylus: tool = EditingTool.ERASER; break;
        case PointerDeviceKind.stylus: tool = EditingTool.STYLUS; break;
        case PointerDeviceKind.mouse: tool = EditingTool.SELECT; break;
        default: tool = EditingTool.MOVE; break;
      }
      _toolData[kind] = tool;
    }
  }

  void _setZoomableState() {
    final zoomEnabled = _toolData[_currentDevice] == null || _toolData[_currentDevice] == EditingTool.MOVE;
    _zoomableKey.currentState!.setState(() => _zoomableKey.currentState!.enabled = zoomEnabled);
    _pointerListenerKey.currentState!.setState(() {
      _pointerListenerKey.currentState!.drawingEnabled = !zoomEnabled;
    });
  }

  void _setScale(double newZoom, {animate = true}) {
    newZoom = max(.1, min(5, newZoom));
    if (newZoom != pageScale) {
      pageScale = newZoom;
      if (animate) {
        _animateTransformation(_zoomController.value.clone()..setDiagonal(Vector4(newZoom, newZoom, 1, 1)));
      } else {
        _zoomController.value.setDiagonal(Vector4(newZoom, newZoom, 1, 1));
      }
      setState(() {});
    }
  }

  Future<void> saveFile({bool export = false}) async {
    setState(() { savingFile = true; });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    try {
      if (_file!.title == null || _file!.title!.isEmpty) {
        await _showTitleDialog();
        if (_file!.title == null || _file!.title!.isEmpty) {
           setState(() { savingFile = false; });
           return; 
        }
      }
      
      String fileName = _file!.title! + '.xopp';
      
      final directory = await getApplicationDocumentsDirectory();
      
      String absolutePath = '${directory.path}/$fileName';
      
      if (_file!.previewImage == null) {
        _file!.previewImage = kTransparentImage;
      }
      
      late FilePickerCross fileData;
      fileData = _file!.toFilePickerCross(filePath: fileName);
      
      File localFile = File(absolutePath);
      await localFile.writeAsBytes(fileData.toUint8List());

      final prefs = await SharedPreferences.getInstance();
      String jsonData = prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]';
      List files = (jsonDecode(jsonData) as List).toList();
      
      bool wasFavorite = files.any((element) => element['path'] == absolutePath && element['favorite'] == true);
      files.removeWhere((element) => element['path'] == absolutePath);
      
      String base64Preview = "";
      if (_file!.previewImage != null) {
         try { base64Preview = base64Encode(_file!.previewImage!); } catch(e) {}
      }

      files.add({
        'preview': base64Preview, 
        'name': _file!.title, 
        'path': absolutePath, 
        'favorite': wasFavorite
      });
      
      await prefs.setString(PreferencesKeys.kRecentFiles, jsonEncode(files));
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Salvato nei documenti dell'app!")));
      
      setState(() { 
        savingFile = false; 
        hasUnsavedChanges = false; 
      });
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore salvataggio: $e")));
      setState(() { savingFile = false; });
    }
  }

  void exportToPdf() async {
    setState(() { savingFile = true; });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    try {
      final pdfDoc = pw.Document();
      for (var xppPage in _file!.pages!) {
        final double width = xppPage.pageSize?.width ?? PdfPageFormat.a4.width;
        final double height = xppPage.pageSize?.height ?? PdfPageFormat.a4.height;
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(width, height, marginAll: 0),
            build: (pw.Context context) {
              return pw.Center(child: pw.Text(_file!.title ?? "Documento"));
            },
          ),
        );
      }
      final Uint8List pdfBytes = await pdfDoc.save();
      String pdfName = (_file!.title ?? "Documento") + ".pdf";
      FilePickerCross pdfFile = FilePickerCross(pdfBytes, type: FileTypeCross.custom, fileExtension: 'pdf', path: pdfName);
      await pdfFile.exportToStorage();

      setState(() { savingFile = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF esportato con successo!")));
    } catch (e) {
      setState(() { savingFile = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore esportazione PDF: $e")));
    }
  }

  void _showPenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Personalizza Tasti Penna'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tasto 1 (Vicino alla punta)', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: buttonDownAction,
                    items: [
                      DropdownMenuItem(value: 'eraser', child: Text('Gomma')),
                      DropdownMenuItem(value: 'select', child: Text('Lazo')),
                      DropdownMenuItem(value: 'highlighter', child: Text('Evidenziatore')),
                    ],
                    onChanged: (v) {
                      setDialogState(() => buttonDownAction = v!);
                      _updateStylusAction('buttonDownAction', v!);
                    },
                  ),
                  SizedBox(height: 20),
                  Text('Tasto 2 (Superiore)', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: buttonUpAction,
                    items: [
                      DropdownMenuItem(value: 'eraser', child: Text('Gomma')),
                      DropdownMenuItem(value: 'select', child: Text('Lazo')),
                      DropdownMenuItem(value: 'highlighter', child: Text('Evidenziatore')),
                    ],
                    onChanged: (v) {
                      setDialogState(() => buttonUpAction = v!);
                      _updateStylusAction('buttonUpAction', v!);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(child: Text('Chiudi'), onPressed: () => Navigator.pop(context))
              ],
            );
          }
        );
      }
    );
  }

  void _updateStylusAction(String key, String newValue) async {
    setState(() {
      if (key == 'buttonDownAction') buttonDownAction = newValue;
      if (key == 'buttonUpAction') buttonUpAction = newValue;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, newValue);
  }

  void _onAnimationReset() {
    _zoomController.value = _animationReset!.value;
    if (!_controllerReset.isAnimating) {
      _animationReset?.removeListener(_onAnimationReset);
      _animationReset = null;
      _controllerReset.reset();
    }
  }

  void _animateTransformation(Matrix4 animateTo) {
    _controllerReset.reset();
    _animationReset = Matrix4Tween(begin: _zoomController.value, end: animateTo).animate(_controllerReset);
    _animationReset!.addListener(_onAnimationReset);
    _controllerReset.forward();
  }

  void _onInteractionStart(ScaleStartDetails details) {
    if (_controllerReset.status == AnimationStatus.forward) {
      _controllerReset.stop();
      _animationReset?.removeListener(_onAnimationReset);
      _animationReset = null;
    }
  }

  @override
  void dispose() {
    _controllerReset.dispose();
    super.dispose();
  }
}