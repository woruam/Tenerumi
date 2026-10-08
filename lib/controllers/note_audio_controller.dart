import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/note_audio.dart';

abstract class NoteAudioBackend {
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]);
}

class AndroidNoteAudioBackend implements NoteAudioBackend {
  static const channel = MethodChannel('online.xournal.mobile/audio');
  static bool _installed = false;
  AndroidNoteAudioBackend() {
    if (!_installed) {
      _installed = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'interrupted')
          await NoteAudioController.owner?.stop();
      });
    }
  }
  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]) =>
      channel.invokeMethod<Object?>(method, arguments);
}

class AudioCursor {
  final String? id;
  final int milliseconds;
  final bool playing;
  const AudioCursor({this.id, this.milliseconds = 0, this.playing = false});
}

class AudioInput {
  final String id;
  final int start;
  final List<int> samples = [];
  AudioInput(this.id, this.start);
}

/// Serializes native operations across tabs; the input path only reads a Stopwatch.
class NoteAudioController extends ChangeNotifier {
  NoteAudioController(
    this.document, {
    required this.onDocumentChanged,
    required this.onModeChanged,
    NoteAudioBackend? backend,
    this.elapsedClock,
  }) : backend = backend ?? AndroidNoteAudioBackend();
  final XppFile document;
  final VoidCallback onDocumentChanged, onModeChanged;
  final NoteAudioBackend backend;
  final int Function()? elapsedClock;
  static NoteAudioController? owner;
  static Future<void>? _queue;
  Future<void>? _closing;
  static Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _queue;
    final result = previous == null
        ? Future<void>.sync(operation)
        : previous.then((_) => operation());
    final recovered = result.catchError((Object _) {});
    _queue = recovered;
    unawaited(
      recovered.then((_) {
        if (identical(_queue, recovered)) _queue = null;
      }),
    );
    return result;
  }

  final cursor = ValueNotifier(const AudioCursor());
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  bool _disposed = false, busy = false, recording = false, listenMode = false;
  bool _polling = false;
  int _pendingCommands = 0;
  String? recordingId, error;
  int _stoppedAt = 0;
  bool get supported =>
      backend is! AndroidNoteAudioBackend ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  int get elapsedMs => elapsedClock?.call() ?? _clock.elapsedMilliseconds;
  int get totalBytes =>
      document.recordings.values.fold(0, (n, r) => n + r.bytes.length);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) {
    if (_disposed) return Future.value();
    _pendingCommands++;
    busy = true;
    _notify();
    final future =
        _enqueue(() async {
          if (_disposed) return;
          try {
            error = null;
            await action();
          } on PlatformException catch (e) {
            error = e.message ?? 'Audio non disponibile';
          } catch (_) {
            error = 'Audio non disponibile';
          }
        }).whenComplete(() {
          busy = --_pendingCommands > 0;
          _notify();
        });
    return future;
  }

  Future<void> _claim() async {
    final previous = owner;
    if (previous != null && previous != this) {
      await previous._stopRecording();
      await previous.backend.invoke('release');
      previous._timer?.cancel();
      previous.cursor.value = const AudioCursor();
      previous._notify();
    }
    owner = this;
  }

  Future<void> start() => _run(() async {
    if (!supported) {
      error = 'Registrazione disponibile su Android';
      return;
    }
    if (recording) return;
    if (totalBytes + maxRecordingBytes > maxAudioBytes) {
      error = 'Limite audio dell’appunto raggiunto (128 MB)';
      return;
    }
    await _claim();
    _timer?.cancel();
    cursor.value = const AudioCursor();
    await backend.invoke('start');
    if (_disposed) {
      await backend.invoke('release');
      owner = null;
      return;
    }
    recordingId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _clock.reset();
    _clock.start();
    recording = true;
    listenMode = false;
    onModeChanged();
    _startTimer();
  });
  Future<void> stop() =>
      !recording && !busy ? Future.value() : _run(_stopRecording);
  Future<void> stopPlayback() => _run(() async {
    if (owner != this || recording) return;
    _timer?.cancel();
    await backend.invoke('release');
    cursor.value = const AudioCursor();
  });
  Future<void> close() {
    dispose();
    return _closing ?? Future.value();
  }

  Future<void> _stopRecording() async {
    if (!recording || owner != this) return;
    _stoppedAt = elapsedMs;
    _clock.stop();
    recording = false;
    _timer?.cancel();
    final id = recordingId!;
    final raw = await backend.invoke('stop');
    if (raw is Map &&
        raw['bytes'] is Uint8List &&
        (raw['duration'] as int? ?? 0) > 0) {
      final bytes = raw['bytes'] as Uint8List;
      if (bytes.isNotEmpty &&
          bytes.length <= maxRecordingBytes &&
          totalBytes + bytes.length <= maxAudioBytes) {
        _stoppedAt = min(_stoppedAt, raw['duration'] as int);
        document.recordings[id] = NoteRecording(
          id,
          raw['duration'] as int,
          bytes,
        );
        onDocumentChanged();
      } else {
        error = 'Registrazione troppo grande';
      }
    } else {
      error = 'Registrazione troppo breve o non disponibile';
    }
    _notify();
  }

  AudioInput? beginInput() =>
      recording ? AudioInput(recordingId!, elapsedMs) : null;
  void sampleInput(AudioInput? input) {
    if (input != null && input.id == recordingId)
      input.samples.add(recording ? elapsedMs : _stoppedAt);
  }

  StrokeAudioLink? endInput(AudioInput? input, int pointCount) {
    if (input == null ||
        input.id != recordingId ||
        (!recording && input.start > _stoppedAt))
      return null;
    final end = recording ? elapsedMs : _stoppedAt;
    return StrokeAudioLink(
      input.id,
      input.start,
      max(input.start, end),
      input.samples.length == pointCount
          ? input.samples
                .map((t) => t.clamp(input.start, max(input.start, end)).toInt())
                .toList()
          : const [],
    );
  }

  Future<void> play(String id, {int position = 0}) => _run(() async {
    if (!supported) {
      error = 'Ascolto disponibile su Android';
      return;
    }
    await _claim();
    await _stopRecording();
    final audio = document.recordings[id];
    if (audio == null) {
      error = 'Audio del tratto non disponibile';
      return;
    }
    _timer?.cancel();
    final target = position.clamp(0, audio.durationMs);
    await backend.invoke('play', {'bytes': audio.bytes, 'position': target});
    if (_disposed) {
      await backend.invoke('release');
      owner = null;
      return;
    }
    cursor.value = AudioCursor(id: id, milliseconds: target, playing: true);
    _startTimer();
  });
  Future<void> pauseOrResume() => _run(() async {
    if (owner != this || cursor.value.id == null) return;
    final old = cursor.value;
    await backend.invoke(old.playing ? 'pause' : 'resume');
    cursor.value = AudioCursor(
      id: old.id,
      milliseconds: old.milliseconds,
      playing: !old.playing,
    );
    if (!old.playing)
      _startTimer();
    else
      _timer?.cancel();
  });
  Future<void> seek(int position) => _run(() async {
    if (owner != this || cursor.value.id == null) return;
    final old = cursor.value;
    final target = position.clamp(0, document.recordings[old.id]!.durationMs);
    await backend.invoke('seek', {'position': target});
    cursor.value = AudioCursor(
      id: old.id,
      milliseconds: target,
      playing: old.playing,
    );
  });
  void setListenMode(bool enabled) {
    listenMode = enabled;
    onModeChanged();
    _notify();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_disposed || _polling || busy || owner != this) return;
    _polling = true;
    try {
      final raw = await backend.invoke('position');
      if (_disposed || owner != this || busy || raw is! Map) return;
      if (recording) {
        cursor.value = AudioCursor(milliseconds: elapsedMs);
        if (raw['recording'] == false || elapsedMs >= maxRecordingMs)
          unawaited(stop());
      } else {
        final old = cursor.value;
        if (old.id == null) return;
        final playing = raw['playing'] == true;
        cursor.value = AudioCursor(
          id: old.id,
          milliseconds: (raw['position'] as int? ?? 0).clamp(
            0,
            document.recordings[old.id]!.durationMs,
          ),
          playing: playing,
        );
        if (!playing) _timer?.cancel();
      }
    } catch (_) {
      _timer?.cancel();
      error = 'Audio interrotto';
      if (recording) unawaited(stop());
      _notify();
    } finally {
      _polling = false;
    }
  }

  Future<void> suspend() async {
    if (recording) await stop();
    if (cursor.value.playing) await pauseOrResume();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _clock.stop();
    // Complete pending start/stop before releasing; another tab must never be released.
    _closing = _enqueue(() async {
      if (owner == this) {
        try {
          await _stopRecording();
          await backend.invoke('release');
        } catch (_) {
        } finally {
          if (owner == this) owner = null;
        }
      }
    });
    cursor.dispose();
    super.dispose();
  }
}
