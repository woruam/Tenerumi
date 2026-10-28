import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/note_audio_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/note_audio_panel.dart';

class CleanupAudio implements NoteAudioBackend {
  final calls = <String>[];
  final starts = <Map<String, Object?>>[];
  final requested = Completer<void>();
  final cleaned = Completer<Object?>();
  final original = Uint8List.fromList([1, 2, 3]);
  bool needsCleanup = true;
  bool recover = false;
  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? args]) async {
    calls.add(method);
    switch (method) {
      case 'start':
        starts.add(Map.of(args!));
        return null;
      case 'stop':
        return {'bytes': original, 'duration': 1000, 'cleanup': needsCleanup};
      case 'cleanSegment':
        if (!requested.isCompleted) requested.complete();
        return cleaned.future;
      case 'recover':
        return recover
            ? [
                {'id': 'recovered', 'state': 'ready', 'duration': 1000},
              ]
            : [];
      case 'readSegment':
        return {'bytes': original, 'duration': 1000, 'cleanup': true};
      case 'position':
        return {'recording': true, 'position': 0, 'playing': false};
      default:
        return null;
    }
  }
}

NoteAudioController controller(
  CleanupAudio backend, {
  XppFile? file,
  int Function()? clock,
}) {
  final audio = NoteAudioController(
    file ?? XppFile.empty(),
    backend: backend,
    onDocumentChanged: () {},
    onModeChanged: () {},
    elapsedClock: clock,
  );
  return audio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cleanup replaces bytes but preserves recording identity, duration and all stroke times', () async {
    final backend = CleanupAudio();
    var now = 100;
    final audio = controller(backend, clock: () => now);
    await audio.start();
    final id = audio.recordingId!;
    final input = audio.beginInput();
    audio.sampleInput(input);
    now = 700;
    audio.sampleInput(input);
    final link = audio.endInput(input, 2)!;
    final stop = audio.stop();
    await backend.requested.future;
    expect(audio.cleaning, isTrue);
    expect(
      audio.document.recordings[id]!.bytes,
      orderedEquals(backend.original),
    );
    final replacement = Uint8List.fromList([4, 5, 6]);
    backend.cleaned.complete({'bytes': replacement, 'applied': true});
    await stop;
    expect(audio.document.recordings[id]!.id, id);
    expect(audio.document.recordings[id]!.durationMs, 1000);
    expect(audio.document.recordings[id]!.bytes, orderedEquals(replacement));
    expect(link.recordingId, id);
    expect(link.startMs, 100);
    expect(link.endMs, 700);
    expect(link.samples, [100, 700]);
    expect(audio.cleaning, isFalse);
    await audio.close();
  });

  test(
    'segment rotation restarts capture without waiting for cleanup',
    () async {
      final backend = CleanupAudio();
      final audio = controller(backend);
      await audio.start();
      final originalId = audio.recordingId!;
      await audio.rotateSegment();
      await backend.requested.future;
      expect(backend.starts.length, 2);
      expect(audio.recording, isTrue);
      expect(audio.recordingId, isNot(originalId));
      expect(audio.cleaning, isTrue);
      expect(audio.beginInput()!.id, audio.recordingId);
      backend.cleaned.complete({
        'bytes': Uint8List.fromList([9]),
        'applied': true,
      });
      backend.needsCleanup = false;
      await audio.stop();
      expect(audio.document.recordings.length, 2);
      expect(audio.document.recordings[originalId]!.bytes, [9]);
      await audio.close();
    },
  );

  for (final fail in [false, true]) {
    test(
      'unavailable cleanup preserves the original: exception=$fail',
      () async {
        final backend = CleanupAudio();
        final audio = controller(backend);
        await audio.start();
        final id = audio.recordingId!;
        final stop = audio.stop();
        await backend.requested.future;
        if (fail) {
          backend.cleaned.completeError(PlatformException(code: 'audio'));
        } else {
          backend.cleaned.complete({
            'bytes': backend.original,
            'applied': false,
          });
        }
        await stop;
        expect(
          audio.document.recordings[id]!.bytes,
          orderedEquals(backend.original),
        );
        expect(audio.cleanupNotice, contains('originale conservato'));
        expect(audio.cleaning, isFalse);
        await audio.close();
      },
    );
  }

  test(
    'ACK waits for recovered audio cleanup before allowing staging deletion',
    () async {
      final backend = CleanupAudio()..recover = true;
      final audio = controller(backend);
      await audio.recoverStaged();
      await backend.requested.future;
      final ack = audio.acknowledge(['recovered']);
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, isNot(contains('ack')));
      backend.cleaned.complete({
        'bytes': Uint8List.fromList([7]),
        'applied': true,
      });
      await ack;
      expect(backend.calls.last, 'ack');
      expect(audio.document.recordings['recovered']!.bytes, [7]);
      await audio.close();
    },
  );

  test('finishing cleanup cannot resurrect a deleted recording', () async {
    final backend = CleanupAudio();
    final audio = controller(backend);
    await audio.start();
    final id = audio.recordingId!;
    final stop = audio.stop();
    await backend.requested.future;
    audio.document.recordings.remove(id);
    backend.cleaned.complete({
      'bytes': Uint8List.fromList([7]),
      'applied': true,
    });
    await stop;
    expect(audio.document.recordings, isEmpty);
    await audio.close();
  });

  test('preferences persist and are passed to capture; active recording freezes them', () async {
    final first = controller(CleanupAudio());
    await first.setCleanupSettings(noise: false, stylusTaps: false);
    await first.close();
    final backend = CleanupAudio()..needsCleanup = false;
    final audio = controller(backend);
    await audio.start();
    expect(backend.starts.single['reduceNoise'], isFalse);
    expect(backend.starts.single['reduceStylusTaps'], isFalse);
    await audio.setCleanupSettings(noise: true, stylusTaps: true);
    expect(audio.reduceNoise, isFalse);
    expect(audio.reduceStylusTaps, isFalse);
    await audio.stop();
    expect(backend.calls, isNot(contains('cleanSegment')));
    await audio.close();
  });

  testWidgets(
    'audio panel exposes both filters and locks them while recording',
    (tester) async {
      final backend = CleanupAudio()..needsCleanup = false;
      final audio = controller(backend);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NoteAudioPanel(audio: audio)),
        ),
      );
      await tester.pumpAndSettle();
      final noise = find.byKey(const ValueKey('audio-noise-reduction'));
      final taps = find.byKey(const ValueKey('audio-stylus-tap-reduction'));
      expect(tester.widget<SwitchListTile>(noise).value, isTrue);
      expect(tester.widget<SwitchListTile>(taps).value, isTrue);
      await tester.tap(noise);
      await tester.pumpAndSettle();
      expect(audio.reduceNoise, isFalse);
      await audio.start();
      await tester.pump();
      expect(tester.widget<SwitchListTile>(noise).onChanged, isNull);
      expect(tester.widget<SwitchListTile>(taps).onChanged, isNull);
      await audio.stop();
      await tester.pumpWidget(const SizedBox());
      await audio.close();
    },
  );
}
