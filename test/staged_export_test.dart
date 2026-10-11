import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/backup_staging_io.dart' as staging;
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'document_storage_test.dart' show TestDocumentsProvider;

class _SavePicker extends FilePickerPlatform {
  Uri? destination;
  String? suggestedName, mime;
  Uint8List? submittedBytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    suggestedName = fileName;
    mime = mimeType;
    submittedBytes = bytes;
    return destination;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('online.xournal.mobile/documents');
  const pdfUri =
      'content://com.android.externalstorage.documents/document/'
      'primary%3ADownload%2FAppunti%20universit%C3%A0.pdf';
  late FilePickerPlatform previousPicker;
  late PathProviderPlatform previousProvider;
  late Directory directory;
  late _SavePicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousPicker = FilePickerPlatform.instance;
    previousProvider = PathProviderPlatform.instance;
    directory = await Directory.systemTemp.createTemp('osi-export-test-');
    PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
    picker = _SavePicker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    FilePickerPlatform.instance = previousPicker;
    PathProviderPlatform.instance = previousProvider;
    await directory.delete(recursive: true);
  });

  testWidgets(
    'PDF export streams the complete staged file to the selected provider',
    (tester) async {
      picker.destination = Uri.parse(pdfUri);
      Uint8List? exported;
      String? sourcePath;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'writeFromFile');
        final args = Map<String, dynamic>.from(call.arguments as Map);
        expect(args['uri'], pdfUri);
        sourcePath = args['source'] as String;
        expect(sourcePath, endsWith('/export.pdf'));
        exported = await File(sourcePath!).readAsBytes();
        return null;
      });
      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final file = XppFile.empty(title: 'Appunti università');
      final controller = CanvasController(autosaveEnabled: false)..init(file);
      try {
        await tester.runAsync(() => controller.exportToPdf(context!));
        await tester.pump();
        expect(find.text('PDF esportato'), findsOneWidget);
        expect(picker.suggestedName, 'Appunti università.pdf');
        expect(picker.mime, 'application/pdf');
        expect(exported, isNotNull);
        expect(latin1.decode(exported!), startsWith('%PDF-'));
        expect(latin1.decode(exported!), contains('/Count 1'));
        expect(controller.savingFile, isFalse);
        expect(identical(controller.file, file), isTrue);
        expect(
          await tester.runAsync(() => File(sourcePath!).exists()),
          isFalse,
        );
      } finally {
        controller.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  test(
    'staged backup retains provider authority and encoded document ID',
    () async {
      const uri = 'content://cloud.example/tree/backup/document/a%2Fb%3Ac.zip';
      picker.destination = Uri.parse(uri);
      final root = await staging.createStaging();
      final source = File('$root/backup.zip');
      final bytes = Uint8List.fromList([80, 75, 3, 4, 1, 2, 3]);
      await source.writeAsBytes(bytes);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'writeFromFile');
        expect(call.arguments['uri'], uri);
        expect(
          await File(call.arguments['source'] as String).readAsBytes(),
          bytes,
        );
        return null;
      });
      expect(
        await FilePickerCross.exportStagedFile(source.path, 'backup.zip'),
        uri,
      );
      expect(picker.mime, 'application/zip');
      expect(await source.exists(), isTrue);
    },
  );

  test('desktop staged export copies and verifies the selected file', () async {
    final source = File('${directory.path}/source.pdf');
    final destination = File('${directory.path}/Appunti con spazi.pdf');
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4\nexample\n%%EOF'));
    await source.writeAsBytes(bytes);
    await destination.writeAsString('old destination');
    picker.destination = Uri.file(destination.path);
    expect(
      await FilePickerCross.exportStagedFile(source.path, 'note.pdf'),
      picker.destination!.toFilePath(),
    );
    expect(await destination.readAsBytes(), bytes);
    expect(await source.readAsBytes(), bytes);
  });

  test('cancelled export performs no document write', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      fail('Cancellation must not write a document');
    });
    expect(
      await FilePickerCross.exportStagedFile('unused.pdf', 'note.pdf'),
      isNull,
    );
  });

  test(
    'incomplete provider paths are rejected rather than treated as local files',
    () async {
      picker.destination = Uri.parse('/document/primary%3ADownload%2Fnote.pdf');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        fail('Do not reconstruct a provider authority from a path');
      });
      await expectLater(
        FilePickerCross.exportStagedFile('unused.pdf', 'note.pdf'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Destinazione di esportazione non supportata',
          ),
        ),
      );
    },
  );

  test(
    'ordinary JSON export retains the complete content URI for future access',
    () async {
      const uri = 'content://provider.example/document/set%2Fcards.json';
      picker.destination = Uri.parse(uri);
      final bytes = Uint8List.fromList(utf8.encode('{"cards":[]}'));
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'retain');
        expect(call.arguments['uri'], uri);
        return true;
      });
      final file = FilePickerCross(bytes);
      expect(await file.exportToStorage(fileName: 'cards.json'), uri);
      expect(file.reopenableGrant, isTrue);
      expect(picker.submittedBytes, bytes);
      expect(picker.mime, 'application/json');
    },
  );
}
