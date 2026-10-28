import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/compat/brand_preferences_io.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tenerumi-brand-');
  });
  tearDown(() async {
    final parent = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await root.resolveSymbolicLinks();
    if (!target.startsWith('$parent${Platform.pathSeparator}tenerumi-brand-')) {
      throw StateError('Unexpected temporary test directory');
    }
    await root.delete(recursive: true);
  });

  test(
    'first branded launch copies preferences and preserves the legacy file',
    () async {
      final source = File('${root.path}/xournalpp/shared_preferences.json');
      await source.parent.create();
      const original =
          '{"flutter.use_dynamic_color":false,"flutter.touchDrawing":true}';
      await source.writeAsString(original);
      final current = Directory('${root.path}/Tenerumi');
      expect(await copyLegacyBrandPreferences(current), isTrue);
      expect(
        await File('${current.path}/shared_preferences.json').readAsString(),
        original,
      );
      expect(await source.readAsString(), original);
      expect(await copyLegacyBrandPreferences(current), isFalse);
    },
  );

  test(
    'new brand preferences are never overwritten by older settings',
    () async {
      final source = File('${root.path}/xournalpp/shared_preferences.json');
      await source.parent.create();
      await source.writeAsString('{"value":"old"}');
      final target = File('${root.path}/Tenerumi/shared_preferences.json');
      await target.parent.create();
      await target.writeAsString('{"value":"new"}');
      expect(await copyLegacyBrandPreferences(target.parent), isFalse);
      expect(await target.readAsString(), '{"value":"new"}');
    },
  );

  test(
    'unreadable old JSON is retained without creating a new preferences file',
    () async {
      final source = File('${root.path}/xournalpp/shared_preferences.json');
      await source.parent.create();
      await source.writeAsString('partial JSON');
      final current = Directory('${root.path}/Tenerumi');
      expect(await copyLegacyBrandPreferences(current), isFalse);
      expect(await source.readAsString(), 'partial JSON');
      expect(await current.exists(), isFalse);
    },
  );
}
