import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

final class _MemoryFile extends PlatformFile {
  final Uint8List bytes;
  _MemoryFile(this.bytes);
  @override
  String get name => 'opened.xopp';
  @override
  Uri get uri => Uri.parse('memory:opened.xopp');
  @override
  String? get path => null;
  @override
  Never get xFile => throw StateError('Memory file has no filesystem path');
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _Picker extends FilePickerPlatform {
  int calls = 0;
  FileType? type;
  List<String>? extensions;
  Future<PlatformFile?> Function() select = () async => null;
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
  }) {
    calls++;
    this.type = type;
    extensions = allowedExtensions;
    return select();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previous = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    addTearDown(() {
      FilePickerPlatform.instance = previous;
      debugDefaultTargetPlatformOverride = null;
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    test('$platform document picker allows both XOPP and PDF', () async {
      debugDefaultTargetPlatformOverride = platform;
      await expectLater(
        FilePickerCross.importFromStorage(
          type: FileTypeCross.custom,
          fileExtension: 'xopp,pdf',
        ),
        throwsA('No file selected.'),
      );
      expect(
        picker.type,
        platform == TargetPlatform.android ? FileType.any : FileType.custom,
      );
      expect(
        picker.extensions,
        platform == TargetPlatform.android ? null : ['xopp', 'pdf'],
      );
    });
  }

  test('Android PDF background picker keeps its PDF filter', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(
      FilePickerCross.importFromStorage(
        type: FileTypeCross.custom,
        fileExtension: 'pdf',
      ),
      throwsA('No file selected.'),
    );
    expect(picker.type, FileType.custom);
    expect(picker.extensions, ['pdf']);
  });

  for (final outcome in ['success', 'cancel', 'error']) {
    testWidgets('home opens device file: $outcome', (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = ThemeController();
      final selected = XppFile.empty()..title = 'Appunto importato';
      picker.select = () async {
        if (outcome == 'error')
          throw const FormatException('Test invalid file');
        if (outcome == 'cancel') return null;
        return _MemoryFile(await selected.toUint8ListAsync());
      };
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(home: OpenPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open file'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('home-open-file')));
        // XOPP decoding runs in a real isolate.
        for (var i = 0; i < 40 && outcome == 'success'; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
          if (find.byType(WorkspacePage).evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(
        find.byType(WorkspacePage),
        outcome == 'success' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(SnackBar),
        outcome == 'error' ? findsOneWidget : findsNothing,
      );
      if (outcome == 'success') {
        final opened = tester
            .widget<WorkspacePage>(find.byType(WorkspacePage))
            .initialFile!;
        expect(opened.title, 'opened');
        expect(opened.documentId, selected.documentId);
        expect(opened.pages!.length, selected.pages!.length);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    });
  }

  testWidgets('home disables open while a picker is pending', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<PlatformFile?>();
    picker.select = () => pending.future;
    final theme = ThemeController();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(home: OpenPage()),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('home-open-file'));
    await tester.tap(action);
    await tester.pump();
    expect(tester.widget<TextButton>(action).onPressed, isNull);
    await tester.tap(action);
    expect(picker.calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(action).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
  });
}
