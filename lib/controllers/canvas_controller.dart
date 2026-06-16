import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'dart:math';

class PageSnapshot {
  final int pageIndex;
  final List<XppContent?> content;
  PageSnapshot(this.pageIndex, this.content);
}

enum EraserMode { pixel, stroke }


class CanvasController extends ChangeNotifier {
  XppFile? file;
  
  Color penColor = Colors.black;
  double penWidth = 2.5;
  Color highlighterColor = const Color(0xFFFFF59D); 
  double highlighterWidth = 15.0;
  EraserMode eraserMode = EraserMode.pixel;
  double eraserWidth = 10.0;

  Map<PointerDeviceKind?, EditingTool> toolData = {};
  PointerDeviceKind? currentDevice = PointerDeviceKind.touch;
  final Map<int, GlobalKey<XppPageStackState>> pageStackKeys = {};

  bool savingFile = false;
  bool shapeRecognition = false;
  bool hasUnsavedChanges = false;
  
  String buttonDownAction = 'eraser';
  String buttonUpAction = 'select';

  bool eraserSnapshotTaken = false;
  List<PageSnapshot> undoStack = [];
  List<PageSnapshot> redoStack = [];

  bool get isPanEnabled => toolData[PointerDeviceKind.stylus] == EditingTool.MOVE;

  void init(XppFile? initialFile) {
    if (file != null) return;
    file = initialFile;
    toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
    toolData[PointerDeviceKind.touch] = EditingTool.MOVE;

    SharedPreferences.getInstance().then((prefs) {
      final enabled = prefs.getBool(PreferencesKeys.kShapeRecognition);
      if (enabled != null) shapeRecognition = enabled;
      final bDown = prefs.getString('buttonDownAction') ?? prefs.getString('stylusButtonAction'); 
      final bUp = prefs.getString('buttonUpAction');
      if (bDown != null) buttonDownAction = bDown;
      if (bUp != null) buttonUpAction = bUp;
      notifyListeners();
    }).catchError((e) {});
  }

  // --- GESTIONE DEI TRATTI (NUOVA LOGICA SMART) ---
  void addNewContent(int pageIndex, XppContent? newContent) {
    if (newContent == null) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    
    file!.pages![pageIndex].layers![0].content ??= [];
    file!.pages![pageIndex].layers![0].content!.add(newContent);
    
    // Forza il ridisegno della tela grafica Xpp
    pageStackKeys[pageIndex]?.currentState?.setPageData(file!.pages![pageIndex]);
    notifyListeners();
  }

  void deleteContent(int pageIndex, List<XppContent> deleted) {
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    file!.pages![pageIndex].layers![0].content!.removeWhere((element) => deleted.contains(element));
    pageStackKeys[pageIndex]?.currentState?.setPageData(file!.pages![pageIndex]);
    notifyListeners();
  }

  void removeLastContent(int pageIndex) {
    if (file!.pages![pageIndex].layers![0].content!.isEmpty) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    file!.pages![pageIndex].layers![0].content!.removeLast();
    pageStackKeys[pageIndex]?.currentState?.setPageData(file!.pages![pageIndex]);
    notifyListeners();
  }

  void filterEraser({required int pageIndex, Offset? coordinates, double? radius}) {
    List<XppContent?> contents = file!.pages![pageIndex].layers![0].content ?? [];
    XppContent? strokeToProcess;

    for (int i = contents.length - 1; i >= 0; i--) {
      final stroke = contents[i];
      if (stroke == null) continue;
      if (stroke.bounds() != null && stroke.bounds()!.inflate(radius ?? 5.0).contains(coordinates!)) { 
        strokeToProcess = stroke; 
        break; 
      }
    }

    if (strokeToProcess != null) {
      if (!eraserSnapshotTaken) { saveSnapshot(pageIndex); eraserSnapshotTaken = true; }
      hasUnsavedChanges = true;
      
      if (eraserMode == EraserMode.stroke) {
        file!.pages![pageIndex].layers![0].content!.remove(strokeToProcess);
      } else {
        final delta = strokeToProcess.eraseWhere(coordinates: coordinates, radius: radius);
        if (delta.affected) {
          final int index = file!.pages![pageIndex].layers![0].content!.indexOf(strokeToProcess);
          file!.pages![pageIndex].layers![0].content!.removeAt(index);
          file!.pages![pageIndex].layers![0].content!.insertAll(index, delta.newContent);
        }
      }
      pageStackKeys[pageIndex]?.currentState?.setPageData(file!.pages![pageIndex]);
      notifyListeners();
    }
  }

  // --- UNDO / REDO / UTILS ---
  void saveSnapshot(int pageIndex) {
    if (file?.pages == null || file!.pages!.isEmpty) return;
    undoStack.add(PageSnapshot(pageIndex, List.from(file!.pages![pageIndex].layers![0].content ?? [])));
    if (undoStack.length > 50) undoStack.removeAt(0);
    redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (undoStack.isEmpty) return;
    final last = undoStack.removeLast();
    redoStack.add(PageSnapshot(last.pageIndex, List.from(file!.pages![last.pageIndex].layers![0].content ?? [])));
    file!.pages![last.pageIndex].layers![0].content = last.content;
    pageStackKeys[last.pageIndex]?.currentState?.setPageData(file!.pages![last.pageIndex]);
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void redo() {
    if (redoStack.isEmpty) return;
    final future = redoStack.removeLast();
    undoStack.add(PageSnapshot(future.pageIndex, List.from(file!.pages![future.pageIndex].layers![0].content ?? [])));
    file!.pages![future.pageIndex].layers![0].content = future.content;
    pageStackKeys[future.pageIndex]?.currentState?.setPageData(file!.pages![future.pageIndex]);
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void setTool(EditingTool t) {
    toolData = Map.from(toolData);
    toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
    toolData[PointerDeviceKind.stylus] = t;
    notifyListeners();
  }

  void addPage() {
    hasUnsavedChanges = true;
    XppPage newPage = XppPage.empty(background: Colors.white);
    newPage.pageSize = file!.pages!.last.pageSize ?? XppPageSize.a4;
    if (newPage.background != null) newPage.background!.size = newPage.pageSize;
    file!.pages!.add(newPage);
    notifyListeners();
  }

  Color getCurrentToolColor() => toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT ? highlighterColor : penColor;
  double getCurrentToolWidth() => toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT ? highlighterWidth : (toolData[PointerDeviceKind.stylus] == EditingTool.ERASER ? eraserWidth : penWidth);
  void setPenProps(Color? c, double? w) { if (c != null) penColor = c; if (w != null) penWidth = w; notifyListeners(); }
  void setHighlighterProps(Color? c, double? w) { if (c != null) highlighterColor = c; if (w != null) highlighterWidth = w; notifyListeners(); }
  void setEraserProps(EraserMode? m, double? w) { if (m != null) eraserMode = m; if (w != null) eraserWidth = w; notifyListeners(); }

  Future<void> saveFile(BuildContext context) async {
    savingFile = true; notifyListeners();
    try {
      if (file!.title == null || file!.title!.isEmpty) return;
      String fileName = '${file!.title!}.xopp';
      final directory = await getApplicationDocumentsDirectory();
      String absolutePath = '${directory.path}/$fileName';
      if (file!.previewImage == null) file!.previewImage = kTransparentImage;
      FilePickerCross fileData = file!.toFilePickerCross(filePath: fileName);
      await File(absolutePath).writeAsBytes(fileData.toUint8List());
      final prefs = await SharedPreferences.getInstance();
      List files = (jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]') as List).toList();
      bool wasFav = files.any((e) => e['path'] == absolutePath && e['favorite'] == true);
      files.removeWhere((e) => e['path'] == absolutePath);
      files.add({'preview': file!.previewImage != null ? base64Encode(file!.previewImage!) : "", 'name': file!.title, 'path': absolutePath, 'favorite': wasFav});
      await prefs.setString(PreferencesKeys.kRecentFiles, jsonEncode(files));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Salvato nei documenti dell'app!")));
      hasUnsavedChanges = false;
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore: $e"))); }
    finally { savingFile = false; notifyListeners(); }
  }

  Future<void> exportToPdf(BuildContext context) async {
    savingFile = true; notifyListeners();
    try {
      final pdfDoc = pw.Document();
      for (var xppPage in file!.pages!) {
        pdfDoc.addPage(pw.Page(pageFormat: PdfPageFormat(xppPage.pageSize?.width ?? PdfPageFormat.a4.width, xppPage.pageSize?.height ?? PdfPageFormat.a4.height, marginAll: 0), build: (pw.Context ctx) => pw.Center(child: pw.Text(file!.title ?? "Documento"))));
      }
      final Uint8List pdfBytes = await pdfDoc.save();
      await FilePickerCross(pdfBytes, type: FileTypeCross.custom, fileExtension: 'pdf', path: "${file!.title ?? "Documento"}.pdf").exportToStorage();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF esportato!")));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore PDF: $e"))); }
    finally { savingFile = false; notifyListeners(); }
  }
}