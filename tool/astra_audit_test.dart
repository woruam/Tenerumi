// A01-A04 are now rejection regressions. Remaining probes document unfixed
// findings of the audited revision; their success does NOT certify safety.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/plugins/plugin_manifest.dart';
import 'package:xournalpp/plugins/plugin_runtime.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';
import 'package:xournalpp/src/document_limits.dart';
import 'package:xournalpp/src/note_backup.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/src/workspace_session.dart';

class _Documents extends PathProviderPlatform {
  final String path;
  _Documents(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<XppFile> parseXml(String xml) => XppFile.fromFilePickerCross(
  FilePickerCross(Uint8List.fromList(GZipEncoder().encode(utf8.encode(xml)))),
  null,
  (_) async => throw StateError('Missing attachment'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform previous;
  setUp(() async {
    // This forensic Flutter test lives in tool/, outside analyzer's test glob.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('osipp-astra-audit-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(temp.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previous;
    final root = Directory.systemTemp.absolute.path;
    if (!temp.absolute.path.startsWith('$root${Platform.pathSeparator}') ||
        !temp.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('osipp-astra-audit-')) {
      throw StateError('Refusing cleanup outside audit temporary directory');
    }
    await temp.delete(recursive: true);
  });

  test(
    'A01 workflow interpolation stops before exceeding its text limit',
    () async {
      final plugin = NotePlugin.parse(
        jsonEncode({
          'apiVersion': 1,
          'id': 'audit.interpolation',
          'name': 'Audit',
          'version': '1',
          'permissions': <String>[],
          'commands': [
            {
              'id': 'run',
              'label': 'Run',
              'steps': [
                {'set': 'payload', 'value': 'a' * 40000},
                {'set': 'payload', 'value': r'${payload}${payload}'},
                {'set': 'payload', 'value': r'${payload}${payload}'},
              ],
            },
          ],
        }),
      );
      final api = PluginApi()..validate(plugin);
      final runtime = PluginRuntime(plugin, api, {});
      await expectLater(
        runtime.run(plugin.commands.first['steps'] as List),
        throwsStateError,
      );
      expect((runtime.variables['payload'] as String).length, 40000);
    },
  );

  test('A03 parser rejects nonfinite and negative page dimensions', () async {
    await expectLater(
      parseXml(
        '<xournal><page width="Infinity" height="-1"><layer/></page></xournal>',
      ),
      throwsFormatException,
    );
  });

  test('A02 compact gzip cannot expand past the configured quota', () async {
    final text = 'A' * (1024 * 1024);
    final xml =
        '<xournal><page width="10" height="10"><layer><text font="Inter" size="12" x="0" y="0" color="black">$text</text></layer></page></xournal>';
    final compressed = Uint8List.fromList(
      GZipEncoder().encode(utf8.encode(xml)),
    );
    expect(compressed.length, lessThan(4096));
    await expectLater(
      XppFile.fromFilePickerCross(
        FilePickerCross(compressed),
        null,
        (_) async => throw StateError('missing'),
        limits: const DocumentLimits(xmlBytes: 65536),
      ),
      throwsFormatException,
    );
  });

  test('A04 backup rejects unrelated local marker named as pixmap', () async {
    final marker = File('${temp.path}/unrelated-marker.txt');
    await marker.writeAsString('INNOCUOUS_ASTRA_MARKER');
    final note = XppFile.empty(title: 'Imported note');
    note.pages!.single.background = XppBackgroundImage(filename: marker.path);
    final path = '${temp.path}/imported.xopp';
    await File(path).writeAsBytes(await note.toUint8ListAsync());
    await RecentDocuments.save(note, path);
    await expectLater(NoteBackup.create(), throwsStateError);
  });

  test('A06 duplicate document ids replace another source recovery', () async {
    final first = await parseXml(
      '<xournal osipp-id="duplicate"><page width="10" height="10"><layer/></page></xournal>',
    );
    final second = await parseXml(
      '<xournal osipp-id="duplicate"><page width="10" height="10"><layer/></page></xournal>',
    );
    first.sourcePath = '${temp.path}/first.xopp';
    second.sourcePath = '${temp.path}/second.xopp';
    await AutosaveStore.save(first, await first.toUint8ListAsync());
    final oldPath = (await AutosaveStore.list()).single['path'] as String;
    await AutosaveStore.save(second, await second.toUint8ListAsync());
    final entries = await AutosaveStore.list();
    expect(entries, hasLength(1));
    expect(entries.single['source'], second.sourcePath);
    expect(await File(oldPath).exists(), isFalse);
  });

  test('A12 workspace prefers old recovery over newer original', () async {
    final old = XppFile.empty(title: 'Old')
      ..modifiedAt = DateTime.utc(2026, 1, 1);
    final path = '${temp.path}/latest.xopp';
    old.sourcePath = path;
    await AutosaveStore.save(old, await old.toUint8ListAsync());
    final latest = old.snapshot()..modifiedAt = DateTime.utc(2026, 1, 2);
    await File(path).writeAsBytes(await latest.toUint8ListAsync());
    await WorkspaceSession.save({
      'tabs': [
        {'id': old.documentId, 'path': path, 'title': 'Note'},
      ],
      'primary': 0,
    });
    final restored = await WorkspaceSession.restore();
    expect(restored!.files.single.modifiedAt, old.modifiedAt);
    expect(restored.files.single.recovered, isTrue);
  });

  test('A08 visible image can exceed decoded cache byte budget', () async {
    final cache = DecodedImageCache(maxBytes: 1);
    final owner = Object();
    final data = Uint8List.fromList(kTransparentImage);
    cache.retain(owner, [data]);
    cache.lookup(data);
    for (var i = 0; i < 100 && cache.byteCount == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(cache.byteCount, greaterThan(cache.maxBytes));
    cache.release(owner);
    expect(cache.byteCount, 0);
    cache.dispose();
  });

  test(
    'Control: native XOPP parser rejects a corrupted gzip checksum',
    () async {
      final bytes = await XppFile.empty().toUint8ListAsync();
      bytes[bytes.length - 8] ^= 1;
      await expectLater(
        XppFile.fromFilePickerCross(
          FilePickerCross(bytes),
          null,
          (_) async => throw StateError('missing'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'A10 unsupported eraser content silently disappears on round trip',
    () async {
      final file = await parseXml(
        '<xournal fileversion="4"><page width="10" height="10"><layer><stroke tool="eraser" color="white" width="2">0 0 5 5</stroke></layer></page></xournal>',
      );
      expect(file.pages!.single.layers!.single.content, isEmpty);
      expect(file.toXmlString(), isNot(contains('tool="eraser"')));
    },
  );
}
