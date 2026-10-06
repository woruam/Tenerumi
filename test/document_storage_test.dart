import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

Future<FilePickerCross> unavailable(String? path) async =>
    throw StateError('Missing file: $path');

Future<XppFile> readXml(String xml, {String? path}) =>
    XppFile.fromFilePickerCross(
      FilePickerCross(
          Uint8List.fromList(GZipEncoder().encode(utf8.encode(xml))),
          path: path),
      null,
      unavailable,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('titles handle Windows, Unix, missing extensions and missing paths', () {
    expect(XppFile.titleFromPath(r'C:\Users\Alice\notes.xopp'), 'notes');
    expect(XppFile.titleFromPath('/folder/my.notes.xopp'), 'my.notes');
    expect(XppFile.titleFromPath('notes'), 'notes');
    expect(XppFile.titleFromPath(null), 'Documento');
    expect(XppFile.empty(title: r'C:\bad/name:*').suggestedFileName,
        'C__bad_name__.xopp');
  });

  test('async document round trip preserves strokes and portable PDF bytes',
      () async {
    final file = XppFile.empty(title: 'notes');
    file.pdfAttachments['background.pdf'] = Uint8List.fromList([1, 2, 3, 4]);
    // A captured native resource is intentionally unsendable; the serializer
    // must replace this UI callback before crossing the isolate boundary.
    final resource = ReceivePort();
    addTearDown(resource.close);
    file.pages!.first.background = XppBackgroundPdf(
        page: 0,
        filename: 'background.pdf',
        onUnavailable: (_) async {
          resource.sendPort.send(null);
          return FilePickerCross(Uint8List(0));
        });
    file.pages!.first.layers!.first.content!.add(XppStroke.byTool(
      tool: XppStrokeTool.PEN,
      color: Colors.black,
      points: [
        XppStrokePoint(x: 1, y: 2, width: 3),
        XppStrokePoint(x: 4, y: 5, width: 3)
      ],
    ));
    file.pages!.first.layers!.first.content!.add(XppImage(
      data: Uint8List.fromList([1, 2]),
      topLeft: Offset.zero,
      bottomRight: const Offset(10, 10),
    ));
    final bytes = await file.toUint8ListAsync();
    final parsed = await XppFile.fromFilePickerCross(
        FilePickerCross(bytes, path: r'C:\notes.xopp'), null, unavailable);
    expect(parsed.sourcePath, r'C:\notes.xopp');
    expect(parsed.pdfAttachments['background.pdf'], [1, 2, 3, 4]);
    expect((parsed.pages!.first.background as XppBackgroundPdf).page, 0);
    expect(parsed.pages!.first.layers!.first.content, hasLength(2));
    expect(
        (parsed.pages!.first.layers!.first.content!.first as XppStroke).points,
        hasLength(2));
  });

  test('native PDF page numbers and omitted filenames follow Xournal format',
      () async {
    final file = await readXml('''<xournal>
      <page width="100" height="200"><background type="pdf" filename="source.pdf" pageno="1"/><layer/></page>
      <page width="100" height="200"><background type="pdf" pageno="2"/><layer/></page>
    </xournal>''', path: 'native.xopp');
    expect((file.pages![0].background as XppBackgroundPdf).page, 0);
    final second = file.pages![1].background as XppBackgroundPdf;
    expect(second.page, 1);
    expect(second.filename, 'source.pdf');
  });

  test('unknown layer nodes do not drop later strokes; whitespace is accepted',
      () async {
    final file = await readXml('''<xournal><page width="100" height="200">
      <background type="solid" style="dotted" color="white"/><layer>
      <unsupported/><stroke tool="pen" color="black" width="2  2">1  2
      3\t4</stroke></layer></page></xournal>''');
    expect(file.pages!.first.background, isA<XppBackgroundSolidDot>());
    final content = file.pages!.first.layers!.first.content!;
    expect(content, hasLength(1));
    expect((content.first as XppStroke).points!.last.y, 4);
  });

  test('saved files reopen at the same path and overwrite existing bytes',
      () async {
    final directory = await Directory.systemTemp.createTemp('osipp-storage-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}note.xopp';
    final first = FilePickerCross(Uint8List.fromList([1, 2]));
    expect(await first.saveToPath(path: path), path);
    expect(await FilePickerCross.exists(path), isTrue);
    await FilePickerCross(Uint8List.fromList([3, 4, 5])).saveToPath(path: path);
    expect((await FilePickerCross.fromInternalPath(path: path)).toUint8List(),
        [3, 4, 5]);
    expect(directory.listSync().whereType<File>().length, 1);
  });

  test('XML entities in user text are decoded exactly once', () async {
    final file = await readXml('''<xournal><page width="100" height="200">
      <background type="solid" style="plain" color="white"/><layer>
      <text color="black" size="12" font="Sans" x="0" y="0">&amp;amp; &lt; &gt;</text>
      </layer></page></xournal>''');
    final text = file.pages!.first.layers!.first.content!.first as XppText;
    expect(text.text, '&amp; < >');
  });

  test('failed replacement does not truncate the original file', () async {
    final directory = await Directory.systemTemp.createTemp('osipp-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final protectedPath = '${directory.path}${Platform.pathSeparator}folder';
    await Directory(protectedPath).create();
    await expectLater(
        FilePickerCross(Uint8List.fromList([1]))
            .saveToPath(path: protectedPath),
        throwsException);
    expect(await Directory(protectedPath).exists(), isTrue);
    expect(directory.listSync().whereType<File>(), isEmpty);
  });

  testWidgets('failed save keeps dirty state and resets saving state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('osipp-save-error-')))!;
    addTearDown(() => directory.delete(recursive: true));
    final controller = CanvasController()
      ..file = (XppFile.empty(title: 'notes')..sourcePath = directory.path)
      ..hasUnsavedChanges = true;
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox).first);
    final result = await tester.runAsync(() => controller.saveFile(context));
    expect(result, isFalse);
    expect(controller.hasUnsavedChanges, isTrue);
    expect(controller.savingFile, isFalse);
  });

  testWidgets(
      'changes made during save remain dirty and are not in saved snapshot',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('osipp-save-race-')))!;
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}notes.xopp';
    final controller = CanvasController()
      ..file = (XppFile.empty(title: 'notes')..sourcePath = path)
      ..hasUnsavedChanges = true;
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox).first);
    final result = await tester.runAsync(() async {
      final pending = controller.saveFile(context);
      controller.file!.pages!.first.layers!.first.content!.add(XppStroke.byTool(
        tool: XppStrokeTool.PEN,
        color: Colors.black,
        points: [XppStrokePoint(x: 1, y: 1, width: 2)],
      ));
      controller.hasUnsavedChanges = true;
      return pending;
    });
    expect(result, isTrue);
    expect(controller.hasUnsavedChanges, isTrue);
    expect(controller.savingFile, isFalse);
    final saved = await tester.runAsync(() async => XppFile.fromFilePickerCross(
        await FilePickerCross.fromInternalPath(path: path), null, unavailable));
    expect(saved!.pages!.first.layers!.first.content, isEmpty);
  });

  testWidgets('new notes with duplicate titles get distinct files',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('osipp-duplicate-')))!;
    addTearDown(() => directory.delete(recursive: true));
    final previousStorage = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
    addTearDown(() => PathProviderPlatform.instance = previousStorage);
    final first = CanvasController()
      ..file = XppFile.empty(title: 'notes')
      ..hasUnsavedChanges = true;
    final second = CanvasController()
      ..file = XppFile.empty(title: 'notes')
      ..hasUnsavedChanges = true;
    second.file!.pages!.first.layers!.first.content!.add(XppStroke.byTool(
      tool: XppStrokeTool.PEN,
      color: Colors.black,
      points: [XppStrokePoint(x: 5, y: 5, width: 3)],
    ));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox).first);
    await tester.runAsync(() async {
      expect(await first.saveFile(context), isTrue);
      expect(await second.saveFile(context), isTrue);
      expect(first.file!.sourcePath, isNot(second.file!.sourcePath));
      final savedFirst = await XppFile.fromFilePickerCross(
          await FilePickerCross.fromInternalPath(path: first.file!.sourcePath!),
          null,
          unavailable);
      final savedSecond = await XppFile.fromFilePickerCross(
          await FilePickerCross.fromInternalPath(
              path: second.file!.sourcePath!),
          null,
          unavailable);
      expect(savedFirst.pages!.first.layers!.first.content, isEmpty);
      expect(savedSecond.pages!.first.layers!.first.content, hasLength(1));
    });
  });
}

class TestDocumentsProvider extends PathProviderPlatform {
  TestDocumentsProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
