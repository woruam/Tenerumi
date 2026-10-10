import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_http.dart';
import 'package:xournalpp/plugins/plugin_http_native.dart';
import 'package:xournalpp/plugins/plugin_manifest.dart';
import 'package:xournalpp/plugins/plugin_manager_page.dart';
import 'package:xournalpp/plugins/plugin_package.dart';
import 'package:xournalpp/plugins/plugin_runtime.dart';
import 'package:xournalpp/plugins/plugin_ui.dart';

import 'plugin_system_test.dart' show canvas, content, source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'invalid form defaults and duplicate choices rejected before UI builds',
    () {
      for (final field in [
        {
          'id': 'x',
          'label': 'X',
          'type': 'choice',
          'options': ['a', 'a'],
        },
        {
          'id': 'x',
          'label': 'X',
          'type': 'choice',
          'options': ['a'],
          'default': 'absent',
        },
        {'id': 'x', 'label': 'X', 'type': 'number', 'default': 'bad'},
        {'id': 'x', 'label': 'X', 'type': 'boolean', 'default': 1},
        {'id': 'x', 'label': 'X', 'type': 'text', 'default': []},
        {'id': 'x', 'label': 'X', 'type': 'text', 'required': 'true'},
      ]) {
        expect(
          () => NotePlugin.parse(source([], inputs: [field])),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'validated manifests and registered permissions cannot be mutated',
    () async {
      final p = NotePlugin.parse(source([], permissions: []));
      expect(
        () => (p.manifest['permissions'] as List).add('storage'),
        throwsUnsupportedError,
      );
      expect(() => p.commands.first['steps'] = [], throwsUnsupportedError);
      final required = {'storage'};
      final api = PluginApi()..register('private', required, (_) => 'secret');
      required.clear();
      await expectLater(api.invoke(p, 'private', {}), throwsStateError);
    },
  );

  Archive package() {
    final manifest = {
      'apiVersion': 1,
      'id': 'test.package',
      'name': 'Test',
      'version': '1',
      'permissions': [],
      'commands': [
        {'id': 'run', 'label': 'Run', 'handler': 'run'},
      ],
    };
    return Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..add(
        ArchiveFile.noCompress(
          'main.js',
          24,
          utf8.encode('export function run() {} '),
        ),
      );
  }

  test('package CRC corruption and directory entries are rejected', () {
    final archive = package();
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    final marker = utf8.encode('export function');
    final at = _index(bytes, marker);
    expect(at, greaterThan(0));
    bytes[at] ^= 1;
    expect(() => decodePluginPackage(bytes), throwsFormatException);
    archive.add(ArchiveFile.directory('lib/'));
    expect(
      () => decodePluginPackage(
        Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
      ),
      throwsFormatException,
    );
  });

  test('ZIP duplicate names cannot disappear during archive decoding', () {
    final archive = package()
      ..add(ArchiveFile.string('evil.js', 'export const x=1;'));
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    final old = utf8.encode('evil.js'), replacement = utf8.encode('main.js');
    var at = _index(bytes, old);
    while (at >= 0) {
      bytes.setRange(at, at + old.length, replacement);
      at = _index(bytes, old);
    }
    expect(() => decodePluginPackage(bytes), throwsFormatException);
  });

  test(
    'forged decompressed size and symlinks are rejected before large inflation',
    () {
      final archive = package()
        ..add(ArchiveFile.string('bomb.js', 'x' * 100000));
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
      final directory = ZipDirectory()..read(InputMemoryStream(bytes));
      final header = directory.fileHeaders.last;
      final centralName = _index(bytes, utf8.encode('bomb.js'));
      final data = ByteData.sublistView(bytes);
      // The local header's uncompressed size is at signature + 22.
      data.setUint32(centralName - 30 + 22, 1, Endian.little);
      // Find the central record for the same name; its size is signature + 24.
      var centralAt = -1;
      for (var i = 0; i < bytes.length - 46; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50 &&
            data.getUint32(i + 42, Endian.little) == header.localHeaderOffset) {
          centralAt = i;
          break;
        }
      }
      expect(centralAt, greaterThan(0));
      data.setUint32(centralAt + 24, 1, Endian.little);
      expect(() => decodePluginPackage(bytes), throwsFormatException);
      data.setUint16(centralAt + 4, 3 << 8, Endian.little);
      data.setUint32(centralAt + 38, 0xa000 << 16, Endian.little);
      expect(() => decodePluginPackage(bytes), throwsFormatException);
    },
  );

  test('malformed legacy Anki state cannot break the plugin UI', () async {
    final plugins = PluginController();
    addTearDown(plugins.dispose);
    await plugins.install(
      source(
        [
          {
            'action': 'state.set',
            'args': {'key': 'cards', 'value': 'bad'},
          },
        ],
        id: 'example.anki',
        permissions: ['storage'],
      ),
    );
    final c = canvas();
    addTearDown(c.dispose);
    await plugins.execute('example.anki', 'run', c);
    expect(plugins.legacyAnkiCards, isEmpty);
  });

  test(
    'oversized host text and repeated geometry expansion cannot commit',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source([
          {
            'action': 'text.add',
            'args': {'text': 'x' * 65537},
          },
        ]),
      );
      await expectLater(
        plugins.execute('test.plugin', 'run', c),
        throwsStateError,
      );
      expect(content(c), isEmpty);
      await plugins.install(
        source([
          {
            'action': 'text.add',
            'args': {'text': 'staged'},
          },
          {
            'repeat': 5,
            'as': 'i',
            'steps': [
              {
                'action': 'content.transform',
                'args': {'ids': 'all', 'scale': 100},
              },
            ],
          },
        ]),
        replace: true,
      );
      await expectLater(
        plugins.execute('test.plugin', 'run', c),
        throwsStateError,
      );
      expect(content(c), isEmpty);
      expect(c.undoStack, isEmpty);
    },
  );

  test(
    'text.update applies its own text limit and leaves original unchanged',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source([
          {
            'action': 'text.add',
            'args': {'text': 'original'},
          },
        ]),
      );
      await plugins.execute('test.plugin', 'run', c);
      await plugins.install(
        source([
          {
            'action': 'text.update',
            'args': {'id': 0, 'text': 'x' * 65537},
          },
        ]),
        replace: true,
      );
      await expectLater(
        plugins.execute('test.plugin', 'run', c),
        throwsStateError,
      );
      expect((content(c).single as XppText).text, 'original');
      expect(c.undoStack, hasLength(1));
    },
  );

  test('cancellation immediately releases a pending provider and ignores late result', () async {
    final entered = Completer<void>(), delayed = Completer<String>();
    final plugins = PluginController(
      extendApi: (api, s) {
        api.register('test.wait', {}, (_) {
          entered.complete();
          return delayed.future;
        });
      },
    );
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await plugins.install(
      source([
        {'action': 'test.wait'},
        {
          'action': 'text.add',
          'args': {'text': 'late'},
        },
      ]),
    );
    final execution = plugins.execute('test.plugin', 'run', c);
    final failed = expectLater(execution, throwsStateError);
    await entered.future;
    plugins.cancel();
    await failed.timeout(const Duration(seconds: 1));
    expect(plugins.running, false);
    expect(content(c), isEmpty);
    await plugins.install(
      source([
        {
          'action': 'text.add',
          'args': {'text': 'next'},
        },
      ]),
      replace: true,
    );
    await plugins.execute('test.plugin', 'run', c);
    delayed.complete('ignored');
    await Future<void>.delayed(Duration.zero);
    expect((content(c).single as XppText).text, 'next');
  });

  test(
    'no HTTP access to local literals, reserved hosts or overridden routing',
    () {
      for (final url in [
        'https://127.0.0.1',
        'https://192.168.1.1',
        'https://[::1]',
        'https://localhost',
        'https://router.local',
        'https://api.internal',
        'http://api.example.com',
        'https://user:pass@api.example.com',
        'https://api.example.com:444',
      ]) {
        final uri = Uri.parse(url);
        expect(() => validatePluginHttpUri(uri, [uri.host]), throwsStateError);
      }
      validatePluginHttpUri(Uri.parse('https://api.example.com/v1'), [
        'api.example.com',
      ]);
      expect(
        () => validatePluginHttpUri(
          Uri.parse('https://api.example.com/${'x' * 8192}'),
          ['api.example.com'],
        ),
        throwsStateError,
      );
      for (final headers in [
        {'Host': 'other.example.com'},
        {'Connection': 'upgrade'},
        {'X-Name': 'a\r\nb'},
      ]) {
        expect(() => validatePluginHttpHeaders(headers), throwsStateError);
      }
      validatePluginHttpHeaders({'Authorization': 'Bearer limited-token'});
    },
  );

  test(
    'DNS rejects all private/reserved answers including IPv6 and mixed answers',
    () async {
      for (final ip in [
        '0.0.0.0',
        '10.0.0.1',
        '100.64.0.1',
        '127.0.0.1',
        '169.254.169.254',
        '172.16.0.1',
        '192.168.1.1',
        '192.0.2.1',
        '198.18.0.1',
        '224.0.0.1',
        '255.255.255.255',
        '::1',
        '::ffff:192.168.1.1',
        'fc00::1',
        'fe80::1',
        '2001:db8::1',
        '2002:7f00:1::1',
      ]) {
        expect(isPublicPluginAddress(InternetAddress(ip)), false, reason: ip);
      }
      await expectLater(
        resolvePluginAddress(
          'api.example.com',
          lookup: (_) async => [
            InternetAddress('8.8.8.8'),
            InternetAddress('10.0.0.1'),
          ],
        ),
        throwsStateError,
      );
      final public = await resolvePluginAddress(
        'api.example.com',
        lookup: (_) async => [InternetAddress('8.8.8.8')],
      );
      expect(public.address, '8.8.8.8');
      expect(
        isPublicPluginAddress(InternetAddress('2606:4700:4700::1111')),
        true,
      );
    },
  );

  testWidgets(
    'invalid plugin form is rejected without a Flutter build failure',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await expectLater(
        pluginUiHost(context).form!({
          'fields': [
            {
              'id': 'x',
              'label': 'X',
              'type': 'choice',
              'options': ['a'],
              'default': 'b',
            },
          ],
        }),
        throwsFormatException,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plugin host closes only its own form on cancellation', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final host = pluginUiHost(context);
    final form = host.form!({
      'title': 'Plugin pending',
      'fields': [
        {'id': 'x', 'label': 'X', 'type': 'text'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('Plugin pending'), findsOneWidget);
    host.close!();
    await tester.pumpAndSettle();
    expect(await form, isNull);
    expect(find.text('Plugin pending'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      pluginUiHost(context).form!({'title': 'x' * 241, 'fields': []}),
      throwsStateError,
    );
    await expectLater(
      pluginUiHost(context).preview!({'title': 'x' * 241, 'text': 'preview'}),
      throwsStateError,
    );
  });

  testWidgets(
    'JavaScript remains visibly disabled with no UI activation route',
    (tester) async {
      tester.view.physicalSize = const Size(380, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await (FontLoader(
          'Inter',
        )..addFont(rootBundle.load('fonts/Inter/Inter-Variable.ttf'))).load();
      });
      final plugins = PluginController();
      addTearDown(plugins.dispose);
      final c = canvas();
      addTearDown(c.dispose);
      await plugins.install(
        jsonEncode({
          'apiVersion': 1,
          'id': 'test.disabled',
          'name': 'Plugin JavaScript',
          'version': '1',
          'runtime': 'javascript',
          'permissions': ['document.write'],
          'modules': {'main.js': 'export function run() {}'},
          'commands': [
            {'id': 'run', 'label': 'Esegui JS', 'handler': 'run'},
          ],
        }),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('plugin-security-proof'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Inter'),
            home: PluginManagerPage(plugins: plugins, canvas: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plugin JavaScript'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nessun interruttore può riattivarlo'),
        findsOneWidget,
      );
      final run = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Esegui JS'),
      );
      expect(run.onPressed, isNull);
      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Plugin JavaScript'),
                matching: find.byType(ExpansionTile),
              ),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, false);
      expect(toggle.onChanged, isNull);
      await tester.ensureVisible(find.text('Esegui JS'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('plugin-security-proof')),
        );
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('docs/validation/plugin-security-disabled-js.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}

int _index(Uint8List bytes, List<int> marker) {
  for (var i = 0; i <= bytes.length - marker.length; i++) {
    if (List.generate(
      marker.length,
      (j) => bytes[i + j] == marker[j],
    ).every((v) => v)) {
      return i;
    }
  }
  return -1;
}
