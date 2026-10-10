import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/plugins/plugin_manifest.dart';
import 'package:xournalpp/plugins/plugin_runtime.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/bounded_archive.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/document_limits.dart';
import 'package:xournalpp/src/note_backup.dart';
import 'package:xournalpp/src/recent_documents.dart';

import 'document_storage_test.dart' show TestDocumentsProvider;

Uint8List gzip(String xml) =>
    Uint8List.fromList(GZipEncoder().encode(utf8.encode(xml)));
String page(String content, {String width = '595', String height = '842'}) =>
    '<page width="$width" height="$height"><layer>$content</layer></page>';
Future<XppFile> parse(
  String content, {
  DocumentLimits limits = DocumentLimits.standard,
}) => XppFile.fromFilePickerCross(
  FilePickerCross(gzip('<xournal>$content</xournal>')),
  null,
  (_) async => throw StateError('External callback forbidden'),
  limits: limits,
);
PluginRuntime runtime([Map<String, dynamic> context = const {}]) =>
    PluginRuntime(
      NotePlugin.parse(
        jsonEncode({
          'apiVersion': 1,
          'id': 'astra.safe',
          'name': 'Safe',
          'version': '1',
          'permissions': [],
          'commands': [
            {'id': 'run', 'label': 'Run', 'steps': []},
          ],
        }),
      ),
      PluginApi(),
      context,
    );
Map<String, Object?> op(String name, List args) => {'op': name, 'args': args};

class CountingCanvas implements Canvas {
  final Rect clip;
  int primitives = 0;
  CountingCanvas(this.clip);
  @override
  Rect getLocalClipBounds() => clip;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #drawCircle ||
        invocation.memberName == #drawLine) {
      primitives++;
    }
    return null;
  }
}

class PdfDocumentStub extends pdfx.PdfDocument {
  PdfDocumentStub(int count)
    : super(sourceName: 'test', id: 'test', pagesCount: count);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PdfPageStub extends pdfx.PdfPage {
  PdfPageStub(double width, double height)
    : super(
        document: PdfDocumentStub(1),
        id: 'page',
        pageNumber: 1,
        width: width,
        height: height,
        autoCloseAndroid: false,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class ContentPickedFile extends PlatformFile {
  @override
  String get name => 'selected.xopp';
  @override
  Uri get uri => Uri.parse('content://documents/selected');
  @override
  Never get xFile => throw StateError('No filesystem resolution');
  @override
  int? lengthSync() => null;
  @override
  Future<int?> length() async => null;
  @override
  Future<Uint8List> readAsBytes() => throw StateError('Unbounded read');
  @override
  Stream<Uint8List> readAsByteStream() =>
      throw StateError('Use bounded native reader');
}

class ContentPicker extends FilePickerPlatform {
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => ContentPickedFile();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('A01', () {
    test(
      'interpolation rejects doubling before replacing the variable',
      () async {
        final r = runtime();
        await r.run([
          {'set': 'payload', 'value': 'a' * 40000},
        ]);
        await expectLater(
          r.run([
            {'set': 'payload', 'value': r'${payload}${payload}'},
          ]),
          throwsStateError,
        );
        expect((r.variables['payload'] as String).length, 40000);
        expect(r.evaluate('a' * 65536), hasLength(65536));
        expect(() => r.evaluate('a' * 65537), throwsStateError);
      },
    );
    test(
      'implicit recursive text conversions and explosive operators reject',
      () {
        final r = runtime({
          'object': {
            'a': [1, 2],
          },
        });
        expect(() => r.evaluate(r'${object}'), throwsStateError);
        expect(
          () => r.evaluate(
            op('concat', [
              {'var': 'object'},
            ]),
          ),
          throwsStateError,
        );
        expect(
          () => r.evaluate(op('replace', ['a' * 40000, 'a', 'aaa'])),
          throwsStateError,
        );
        expect(
          () => r.evaluate(op('split', ['a' * 10001, ''])),
          throwsStateError,
        );
      },
    );
    test('shared lists count at every occurrence in intermediate results', () {
      final r = runtime({'shared': List.filled(1000, null)});
      expect(
        () => r.evaluate(List.filled(101, {'var': 'shared'})),
        throwsStateError,
      );
      Object? nested;
      for (var i = 0; i < 60; i++) {
        nested = [nested];
      }
      final deep = runtime({'nested': nested});
      Object? expression = {'var': 'nested'};
      for (var i = 0; i < 6; i++) {
        expression = [expression];
      }
      expect(() => deep.evaluate(expression), throwsStateError);
    });
    test(
      'environment budget also applies across variables and API results',
      () async {
        final r = runtime({'shared': List.filled(2000, null)});
        var rejected = false;
        for (var i = 0; i < 60; i++) {
          try {
            await r.run([
              {
                'set': 'v$i',
                'value': {'var': 'shared'},
              },
            ]);
          } on StateError {
            rejected = true;
            expect(r.variables.containsKey('v$i'), isFalse);
            break;
          }
        }
        expect(rejected, isTrue);
        final oversized = 'a' * (1024 * 1024);
        expect(
          () => runtime({for (var i = 0; i < 25; i++) 'v$i': oversized}),
          throwsStateError,
        );
        final actionRuntime = runtime();
        actionRuntime.api.register(
          'result',
          {},
          (_) => List.filled(100001, null),
        );
        await expectLater(
          actionRuntime.run([
            {'action': 'result', 'as': 'answer'},
          ]),
          throwsStateError,
        );
        expect(actionRuntime.variables.containsKey('answer'), isFalse);
      },
    );
  });

  group('A02', () {
    test('selected content URI uses the bounded native channel and checks its response', () async {
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = ContentPicker();
      const channel = MethodChannel('online.xournal.mobile/documents');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var bytes = Uint8List.fromList([1, 2, 3]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'read');
        expect(call.arguments['uri'], 'content://documents/selected');
        expect(call.arguments['maxBytes'], 3);
        return bytes;
      });
      addTearDown(() {
        FilePickerPlatform.instance = previous;
        messenger.setMockMethodCallHandler(channel, null);
      });
      final selected = await FilePickerCross.importFromStorage(maxBytes: 3);
      expect(selected.path, 'content://documents/selected');
      expect(selected.toUint8List(), [1, 2, 3]);
      bytes = Uint8List.fromList([1, 2, 3, 4]);
      await expectLater(
        FilePickerCross.importFromStorage(maxBytes: 3),
        throwsFormatException,
      );
    });
    test('GZIP checks actual output, CRC, truncation and multiple members', () {
      final compressed = gzip('a' * (1024 * 1024));
      expect(
        () => decodeBoundedGzip(compressed, maxInput: 4096, maxOutput: 65536),
        throwsFormatException,
      );
      final good = gzip('hello');
      expect(
        utf8.decode(decodeBoundedGzip(good, maxInput: 128, maxOutput: 5)),
        'hello',
      );
      final corrupt = Uint8List.fromList(good)..[good.length - 8] ^= 1;
      expect(
        () => decodeBoundedGzip(corrupt, maxInput: 128, maxOutput: 5),
        throwsFormatException,
      );
      expect(
        () => decodeBoundedGzip(
          Uint8List.sublistView(good, 0, good.length - 1),
          maxInput: 128,
          maxOutput: 5,
        ),
        throwsA(anything),
      );
      final members = Uint8List.fromList([...good, ...good]);
      expect(
        () => decodeBoundedGzip(members, maxInput: 128, maxOutput: 9),
        throwsFormatException,
      );
    });
    test(
      'output refuses the offending write and keeps its previous length',
      () {
        final output = LimitedArchiveOutput(4)..writeBytes([1, 2, 3, 4]);
        expect(
          () => output.writeBackReference(1, 1000000),
          throwsFormatException,
        );
        expect(output.length, 4);
      },
    );
    test(
      'stream reader stops and cancels when actual bytes exceed the quota',
      () async {
        var cancelled = false;
        final stream = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final reading = readLimitedBytes(stream.stream, 4);
        stream.add([1, 2, 3]);
        stream.add([4, 5]);
        await expectLater(reading, throwsFormatException);
        expect(cancelled, isTrue);
        await stream.close();
        expect(await readLimitedBytes(Stream.value([1, 2, 3, 4]), 4), [
          1,
          2,
          3,
          4,
        ]);
      },
    );
    test(
      'forged ZIP sizes and compressed symlinks reject before extraction',
      () {
        final archive = Archive()
          ..add(ArchiveFile('notes/0.xopp', 100000, List.filled(100000, 65)));
        final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
        final data = ByteData.sublistView(bytes);
        final central = data.getUint32(bytes.length - 6, Endian.little);
        Map<String, Uint8List> decode(Uint8List input) => decodeBoundedZip(
          input,
          maxInput: 1024 * 1024,
          maxOutput: 200000,
          maxEntries: 2,
          entryLimit: (_) => 200000,
        );
        expect(decode(bytes).values.single, hasLength(100000));
        final fake = Uint8List.fromList(bytes);
        ByteData.sublistView(fake)
          ..setUint32(22, 4, Endian.little)
          ..setUint32(central + 24, 4, Endian.little);
        expect(() => decode(fake), throwsFormatException);
        final link = Uint8List.fromList(bytes);
        ByteData.sublistView(link)
            .setUint32(central + 38, 0xa1ff0000, Endian.little);
        expect(() => decode(link), throwsFormatException);
        final encrypted = Uint8List.fromList(bytes);
        ByteData.sublistView(encrypted).setUint16(6, 1, Endian.little);
        expect(() => decode(encrypted), throwsFormatException);
      },
    );
    test('expanded XML, nesting, nodes, pages, layers and points have quotas', () async {
      await expectLater(
        parse(
          page(
            '<text font="Inter" size="12" x="0" y="0" color="black">${'a' * 65536}</text>',
          ),
          limits: const DocumentLimits(xmlBytes: 1024),
        ),
        throwsFormatException,
      );
      await expectLater(
        parse('${'<unknown>' * 20}${page('')}${'</unknown>' * 20}'),
        throwsFormatException,
      );
      await expectLater(
        parse(page(''), limits: const DocumentLimits(nodes: 3)),
        throwsFormatException,
      );
      await expectLater(
        parse(page('') + page(''), limits: const DocumentLimits(pages: 1)),
        throwsFormatException,
      );
      await expectLater(
        parse(
          '<page width="10" height="10"><layer/><layer/></page>',
          limits: const DocumentLimits(layers: 1),
        ),
        throwsFormatException,
      );
      await expectLater(
        parse(
          page(
            '<stroke tool="pen" color="black" width="1">0 0 1 1 2 2</stroke>',
          ),
          limits: const DocumentLimits(points: 2),
        ),
        throwsFormatException,
      );
    });
    test('media quota includes duplicate attachments, audio and cards', () async {
      await expectLater(
        parse(
          '<pdf-attachment name="a">AQID</pdf-attachment>${page('')}',
          limits: const DocumentLimits(mediaBytes: 2),
        ),
        throwsFormatException,
      );
      await expectLater(
        parse(
          '<pdf-attachment name="a">AQ==</pdf-attachment><pdf-attachment name="a">Ag==</pdf-attachment>${page('')}',
        ),
        throwsFormatException,
      );
      await expectLater(
        parse(
          '<osipp-audio id="x" duration="1">AQID</osipp-audio>${page('')}',
          limits: const DocumentLimits(mediaBytes: 2),
        ),
        throwsFormatException,
      );
      await expectLater(
        parse(
          '<osipp-flashcard>{"front":{"image":"AQID"}}</osipp-flashcard>${page('')}',
          limits: const DocumentLimits(mediaBytes: 2),
        ),
        throwsFormatException,
      );
      expect(
        () => validateDocumentJsonText('${'[' * 33}0${']' * 33}'),
        throwsFormatException,
      );
    });
    test(
      'DOCTYPE rejects and one valid page is required at the root',
      () async {
        await expectLater(parse(''), throwsFormatException);
        await expectLater(
          parse('<unknown>${page('')}</unknown>'),
          throwsFormatException,
        );
        expect(
          (await parse('<preview>?</preview>${page('')}')).pages,
          hasLength(1),
        );
        final quota = DocumentImportBudget(const DocumentLimits(mediaBytes: 2));
        expect(
          () => quota.media('AQID', invalidFallback: Uint8List(0)),
          throwsFormatException,
        );
        expect(quota.mediaBytes, 0);
        await expectLater(
          XppFile.fromFilePickerCross(
            FilePickerCross(
              gzip('<!DOCTYPE xournal><xournal>${page('')}</xournal>'),
            ),
            null,
            (_) async => throw StateError('missing'),
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('A03', () {
    for (final number in ['NaN', 'Infinity', '-Infinity', '0', '-1', '20001']) {
      test('invalid page dimension $number rejects', () async {
        await expectLater(
          parse(page('', width: number)),
          throwsFormatException,
        );
      });
    }
    test(
      'invalid text, rectangles, stroke coordinates/widths/erasures reject',
      () async {
        for (final content in [
          '<text font="Inter" size="-1" x="0" y="0" color="black">x</text>',
          '<text font="Inter" size="12" x="NaN" y="0" color="black">x</text>',
          '<image left="5" top="0" right="1" bottom="10">AQ==</image>',
          '<teximage text="x" color="black" left="5" top="0" right="1" bottom="10"/>',
          '<stroke tool="pen" color="black" width="1">0 0 1</stroke>',
          '<stroke tool="pen" color="black" width="-1">0 0</stroke>',
          '<stroke tool="pen" color="black" width="1">100001 0</stroke>',
          '<stroke tool="pen" color="black" width="1" osipp-erasures="0 0 100001 0 1">0 0</stroke>',
        ]) {
          await expectLater(parse(page(content)), throwsFormatException);
        }
        final valid = await parse(
          page(
            '<stroke tool="pen" color="black" width="0">-5 -10 0 0</stroke>',
          ),
        );
        expect(valid.pages, hasLength(1));
      },
    );
    test('PDF references and native page geometry reject before rendering', () async {
      for (final n in ['0', '-1', '10001', 'NaN']) {
        await expectLater(
          parse(
            '<page width="10" height="10"><background type="pdf" filename="a" pageno="$n"/><layer/></page>',
          ),
          throwsFormatException,
        );
      }
      expect(
        () => validatePdfPage(PdfDocumentStub(3), 3),
        throwsFormatException,
      );
      expect(
        () => validatePdfPage(PdfDocumentStub(0), 0),
        throwsFormatException,
      );
      expect(
        () => validatePdfSize(PdfPageStub(double.nan, 10)),
        throwsFormatException,
      );
      expect(
        () => validatePdfSize(PdfPageStub(10, 20001)),
        throwsFormatException,
      );
      validatePdfSize(PdfPageStub(595, 842));
    });
    test('grid work depends on visible area and has a primitive budget', () {
      final canvas = CountingCanvas(const Rect.fromLTWH(100, 100, 50, 50));
      paintPaperBackground(
        canvas,
        const Size(20000, 20000),
        XppBackgroundSolidDot(),
      );
      expect(canvas.primitives, lessThan(1200));
      final full = CountingCanvas(const Rect.fromLTWH(0, 0, 20000, 20000));
      paintPaperBackground(
        full,
        const Size(20000, 20000),
        XppBackgroundSolidDot(),
      );
      expect(full.primitives, lessThanOrEqualTo(180000));
    });
  });

  group('A04', () {
    testWidgets('missing backgrounds expose explicit selection in the editor', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final file = XppFile.empty(title: 'Missing');
      file.pages!.single.background = XppBackgroundImage(
        filename: '../private.png',
      );
      final ctrl = CanvasController(autosaveEnabled: false)..file = file;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasPage(
              controller: ctrl,
              file: file,
              showInternalToolbar: false,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Seleziona allegato di sfondo'), findsOneWidget);
      file.pages!.single.infinite = true;
      ctrl.notifyListeners();
      await tester.pump();
      expect(find.text('Seleziona allegato di sfondo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
    });
    test('document references never invoke an external callback', () async {
      var reads = 0;
      for (final name in [
        r'C:\private\file.pdf',
        '../private.pdf',
        r'\\server\share\file.pdf',
        'content://private/file',
      ]) {
        final file = await XppFile.fromFilePickerCross(
          FilePickerCross(
            gzip(
              '<xournal><page width="10" height="10"><background type="pdf" filename="$name" pageno="1"/><layer/></page></xournal>',
            ),
          ),
          null,
          (_) async {
            reads++;
            return FilePickerCross(Uint8List.fromList([1]));
          },
        );
        final bg = file.pages!.single.background as XppBackgroundPdf;
        await expectLater(bg.onUnavailable(name), throwsStateError);
        expect(file.pdfAttachments, isEmpty);
      }
      expect(reads, 0);
    });
    test('backup excludes unselected local resources; explicit attachment survives transfer', () async {
      SharedPreferences.setMockInitialValues({});
      final oldProvider = PathProviderPlatform.instance;
      final temp = await Directory.systemTemp.createTemp('osipp-astra-fixes-');
      addTearDown(() async {
        PathProviderPlatform.instance = oldProvider;
        final root = Directory.systemTemp.absolute.path;
        expect(
          temp.absolute.path.startsWith('$root${Platform.pathSeparator}'),
          isTrue,
        );
        expect(
          temp.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('osipp-astra-fixes-'),
          isTrue,
        );
        await temp.delete(recursive: true);
      });
      PathProviderPlatform.instance = TestDocumentsProvider(temp.path);
      final marker = File('${temp.path}/unrelated.txt');
      await marker.writeAsString('INNOCUOUS_ASTRA_MARKER');
      final note = XppFile.empty(title: 'External');
      note.pages!.single.background = XppBackgroundImage(filename: marker.path);
      final path = '${temp.path}/note.xopp';
      await File(path).writeAsBytes(await note.toUint8ListAsync());
      await RecentDocuments.save(note, path);
      await expectLater(NoteBackup.create(), throwsStateError);
      note.attachSelectedBackground(
        marker.path,
        FilePickerCross(Uint8List.fromList([1, 2, 3])),
      );
      await File(path).writeAsBytes(await note.toUint8ListAsync());
      final backup = await NoteBackup.create();
      final reopened = (await NoteBackup.inspect(backup.bytes))
          .notes
          .single
          .file;
      expect(reopened.pdfAttachments[marker.path], [1, 2, 3]);
      expect((reopened.pages!.single.background as XppBackgroundImage).data, [
        1,
        2,
        3,
      ]);
    });
  });
}
