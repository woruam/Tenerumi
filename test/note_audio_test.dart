import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/controllers/note_audio_controller.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/note_audio_panel.dart';
import 'package:xournalpp/widgets/audio_timeline_overlay.dart';
import 'package:xournalpp/src/editing_tool.dart';

import 'pomodoro_appearance_test.dart' show capture;

class FakeAudio implements NoteAudioBackend {
  final calls = <String>[];
  bool recording = false, playing = false;
  int position = 0;
  Completer<Object?>? pendingStart;
  bool deny = false;
  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? args]) async {
    calls.add(method);
    switch (method) {
      case 'start':
        if (deny)
          throw PlatformException(
            code: 'permission',
            message: 'Permesso microfono negato',
          );
        if (pendingStart != null) await pendingStart!.future;
        recording = true;
      case 'stop':
        recording = false;
        return {
          'bytes': Uint8List.fromList([1, 2, 3]),
          'duration': 1000,
        };
      case 'play':
        playing = true;
        position = args!['position'] as int;
      case 'pause':
        playing = false;
      case 'resume':
        playing = true;
      case 'seek':
        position = args!['position'] as int;
      case 'release':
        recording = false;
        playing = false;
      case 'position':
        return {
          'position': position,
          'playing': playing,
          'recording': recording,
        };
    }
    return null;
  }
}

XppStroke stroke() => XppStroke.byTool(
  tool: XppStrokeTool.PEN,
  color: Colors.black,
  points: [
    XppStrokePoint(x: 30, y: 30, width: 3),
    XppStrokePoint(x: 120, y: 30, width: 3),
    XppStrokePoint(x: 120, y: 100, width: 3),
  ],
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('portable audio survives isolate serialization, snapshots, clone and pixel eraser', () async {
    final f = XppFile.empty();
    final bytes = Uint8List.fromList([1, 2, 3]);
    f.recordings['rec'] = NoteRecording('rec', 1000, bytes);
    final ink = stroke()
      ..audioLink = StrokeAudioLink('rec', 100, 700, [100, 300, 700]);
    f.pages!.first.layers!.first.content!.add(ink);
    final snapshot = f.snapshot();
    expect(snapshot.recordings['rec'], same(f.recordings['rec']));
    expect(
      () => snapshot.recordings['rec']!.bytes[0] = 7,
      throwsUnsupportedError,
    );
    expect((cloneContent(ink) as XppStroke).audioLink, same(ink.audioLink));
    final cut = ink.eraseAlong(coordinates: const Offset(80, 30), radius: 3);
    expect((cut.newContent.first as XppStroke).audioLink, same(ink.audioLink));
    final parsed = await XppFile.fromFilePickerCross(
      FilePickerCross(
        await snapshot.serializeSnapshotAsync(),
        path: '/note.xopp',
      ),
      null,
      (_) async => throw StateError('missing'),
    );
    expect(parsed.recordings['rec']!.bytes, [1, 2, 3]);
    final restored =
        parsed.pages!.first.layers!.first.content!.first as XppStroke;
    expect(restored.audioLink!.samples, [100, 300, 700]);
    expect(restored.audioLink!.startMs, 100);
  });
  test(
    'malformed optional audio metadata is bounded and leaves notes readable',
    () {
      final xml = XmlDocument.parse(
        '<root><osipp-audio id="../bad" duration-ms="20">AQ==</osipp-audio><osipp-audio id="valid" duration-ms="20">bad!</osipp-audio><osipp-audio id="ok" duration-ms="20">AQ==</osipp-audio></root>',
      );
      expect(NoteRecording.decode(xml.rootElement.childElements).keys, ['ok']);
      expect(
        StrokeAudioLink.decode(
          XmlDocument.parse(
            '<stroke osipp-audio-id="ok" osipp-audio-start="-1" osipp-audio-end="20"/>',
          ).rootElement,
          1,
        ),
        isNull,
      );
      final link = StrokeAudioLink.decode(
        XmlDocument.parse(
          '<stroke osipp-audio-id="ok" osipp-audio-start="0" osipp-audio-end="20" osipp-audio-times="10 5"/>',
        ).rootElement,
        2,
      )!;
      expect(link.samples, isEmpty);
    },
  );
  test(
    'input timing freezes at stop and native owner moves safely across tabs',
    () async {
      var now = 100;
      final backend = FakeAudio();
      var changed = 0;
      final a = NoteAudioController(
        XppFile.empty(),
        backend: backend,
        elapsedClock: () => now,
        onDocumentChanged: () => changed++,
        onModeChanged: () {},
      );
      final b = NoteAudioController(
        XppFile.empty(),
        backend: backend,
        onDocumentChanged: () {},
        onModeChanged: () {},
      );
      await a.start();
      final input = a.beginInput();
      a.sampleInput(input);
      now = 200;
      a.sampleInput(input);
      now = 400;
      await b.start();
      expect(a.recording, false);
      expect(changed, 1);
      expect(backend.calls.take(4), ['start', 'stop', 'release', 'start']);
      now = 900;
      final link = a.endInput(input, 2)!;
      expect(link.startMs, 100);
      expect(link.endMs, 400);
      expect(link.samples, [100, 200]);
      await a.close();
      expect(backend.recording, true);
      await b.close();
      expect(backend.recording, false);
      expect(NoteAudioController.owner, isNull);
    },
  );
  test(
    'permission denial and disposal during pending start release resources',
    () async {
      final backend = FakeAudio()..deny = true;
      final audio = NoteAudioController(
        XppFile.empty(),
        backend: backend,
        onDocumentChanged: () {},
        onModeChanged: () {},
      );
      await audio.start();
      expect(audio.error, contains('Permesso'));
      expect(audio.recording, false);
      backend.deny = false;
      backend.pendingStart = Completer<Object?>();
      final starting = audio.start();
      await Future<void>.delayed(Duration.zero);
      final closing = audio.close();
      backend.pendingStart!.complete(null);
      await starting;
      await closing;
      expect(backend.calls.last, 'release');
      expect(backend.recording, false);
      expect(NoteAudioController.owner, isNull);
    },
  );
  testWidgets(
    'playback uses native clock; seeking, suspend and close stop timers',
    (tester) async {
      final backend = FakeAudio();
      final f = XppFile.empty()
        ..recordings['rec'] = NoteRecording('rec', 1000, Uint8List(3));
      final audio = NoteAudioController(
        f,
        backend: backend,
        onDocumentChanged: () {},
        onModeChanged: () {},
      );
      await audio.play('rec', position: 100);
      backend.position = 450;
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.cursor.value.milliseconds, 450);
      await audio.seek(900);
      expect(backend.position, 900);
      await audio.suspend();
      expect(backend.playing, false);
      final calls = backend.calls.length;
      await tester.pump(const Duration(seconds: 1));
      expect(backend.calls.length, calls);
      await audio.pauseOrResume();
      backend.playing = false;
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.cursor.value.playing, false);
      await audio.close();
      final end = backend.calls.length;
      await tester.pump(const Duration(seconds: 1));
      expect(backend.calls.length, end);
    },
  );
  testWidgets(
    'recorded stylus preserves samples/pressure; canceled strokes never associate audio',
    (tester) async {
      var now = 100;
      final backend = FakeAudio();
      final audio = NoteAudioController(
        XppFile.empty(),
        backend: backend,
        elapsedClock: () => now,
        onDocumentChanged: () {},
        onModeChanged: () {},
      );
      await audio.start();
      final inks = <XppStroke>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PointerListener(
            audio: audio,
            color: Colors.black,
            toolData: const {PointerDeviceKind.stylus: EditingTool.STYLUS},
            onNewContent: (c) => inks.add(c! as XppStroke),
            child: const SizedBox(width: 300, height: 300),
          ),
        ),
      );
      var g = await tester.startGesture(
        const Offset(30, 30),
        kind: PointerDeviceKind.stylus,
      );
      now = 200;
      await g.updateWithCustomEvent(
        const PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset(60, 60),
          pressure: .8,
          pressureMax: 1,
        ),
      );
      now = 300;
      await g.up();
      await tester.pump();
      expect(inks.single.audioLink!.samples, [100, 200]);
      expect(inks.single.audioLink!.endMs, 300);
      expect(inks.single.points, hasLength(2));
      expect(
        inks.single.points![1].width,
        lessThan(inks.single.points![0].width!),
      );
      g = await tester.startGesture(
        const Offset(70, 70),
        kind: PointerDeviceKind.stylus,
      );
      await g.cancel();
      expect(inks, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await audio.close();
    },
  );
  testWidgets(
    'listen mode seeks a stroke without creating ink or invoking eraser buttons',
    (tester) async {
      final audio = NoteAudioController(
        XppFile.empty(),
        backend: FakeAudio(),
        onDocumentChanged: () {},
        onModeChanged: () {},
      );
      audio.setListenMode(true);
      var taps = 0, ink = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PointerListener(
            audio: audio,
            onListenAt: (_) => taps++,
            onNewContent: (_) => ink++,
            toolData: const {PointerDeviceKind.stylus: EditingTool.STYLUS},
            child: const SizedBox(width: 300, height: 300),
          ),
        ),
      );
      final g = await tester.startGesture(
        const Offset(30, 30),
        kind: PointerDeviceKind.stylus,
      );
      await g.up();
      expect(taps, 1);
      expect(ink, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await audio.close();
    },
  );
  test(
    'cross-document paste carries immutable recording without copying bytes',
    () async {
      final clipboard = SelectionClipboard();
      final r = NoteRecording('rec', 1000, Uint8List(5));
      final ink = stroke()..audioLink = StrokeAudioLink('rec', 100, 700);
      clipboard.copy([ink], audio: {'rec': r});
      final canvas = CanvasController(
        autosaveEnabled: false,
        clipboard: clipboard,
      )..init(XppFile.empty());
      final pasted = canvas.pasteSelection(0, const Offset(100, 100));
      expect(canvas.file!.recordings['rec'], same(r));
      expect((pasted.single as XppStroke).audioLink, same(ink.audioLink));
      canvas.undo();
      expect(canvas.activeLayer(0).content, isEmpty);
      canvas.redo();
      expect(
        (canvas.activeLayer(0).content!.single as XppStroke)
            .audioLink!
            .recordingId,
        'rec',
      );
      canvas.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  testWidgets(
    'overlay advances sample cursor without modifying ink and panel fits phone',
    (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = XppFile.empty()
        ..recordings['rec'] = NoteRecording('rec', 1000, Uint8List(3));
      final ink = stroke()
        ..audioLink = StrokeAudioLink('rec', 100, 700, [100, 300, 700]);
      f.pages!.first.layers!.first.content!.add(ink);
      final audio = NoteAudioController(
        f,
        backend: FakeAudio(),
        onDocumentChanged: () {},
        onModeChanged: () {},
      );
      audio.cursor.value = const AudioCursor(
        id: 'rec',
        milliseconds: 350,
        playing: true,
      );
      final before = ink.toXmlElement().toXmlString();
      final key = GlobalKey();
      await tester.runAsync(() async {
        for (final font in {
          'VT323': 'fonts/VT323/VT323-Regular.ttf',
          'Inter': 'fonts/Inter/Inter-Variable.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppAppearance.buildTheme(ThemeController(), null),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: ColoredBox(
                      color: Colors.white,
                      child: SizedBox.expand(
                        child: AudioTimelineOverlay(
                          page: f.pages!.first,
                          audio: audio,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: NoteAudioPanel(audio: audio)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final data = await tester.runAsync(() async {
        final img = await boundary.toImage();
        try {
          return await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          img.dispose();
        }
      });
      int blueAt(int x, int y) => data!.getUint8((y * 380 + x) * 4 + 2);
      expect(
        blueAt(120, 30),
        lessThan(255),
      ); // Cyan cursor at the second input sample.
      expect(blueAt(120, 100), 255); // Future sample remains white.
      expect(ink.toXmlElement().toXmlString(), before);
      await capture(tester, key, 'audio-timeline-panel');
      audio.cursor.value = const AudioCursor(id: 'rec', milliseconds: 750);
      await tester.pump();
      expect(ink.toXmlElement().toXmlString(), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await audio.close();
    },
  );
}
