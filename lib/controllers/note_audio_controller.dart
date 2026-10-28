import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/compat/audio_platform_stub.dart'
    if (dart.library.io) 'package:xournalpp/src/compat/audio_platform_io.dart';

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
        if (call.method == 'segmentReady')
          await NoteAudioController.owner?.rotateSegment();
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
  }) : backend = backend ?? AndroidNoteAudioBackend() {
    _settingsReady = _loadCleanupSettings();
  }
  final XppFile document;
  final VoidCallback onDocumentChanged, onModeChanged;
  final NoteAudioBackend backend;
  final int Function()? elapsedClock;
  static const noisePreference = 'audio_reduce_noise';
  static const tapsPreference = 'audio_reduce_stylus_taps';
  bool reduceNoise = true, reduceStylusTaps = true;
  String? cleanupNotice;
  late final Future<void> _settingsReady;
  final Map<String, Future<void>> _cleanupJobs = {};
  bool get cleaning => _cleanupJobs.isNotEmpty;

  Future<void> _loadCleanupSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      reduceNoise = prefs.getBool(noisePreference) ?? true;
      reduceStylusTaps = prefs.getBool(tapsPreference) ?? true;
      _notify();
    } catch (_) {
      /* Capture remains available when preferences are unavailable. */
    }
  }

  Future<void> setCleanupSettings({bool? noise, bool? stylusTaps}) async {
    await _settingsReady;
    if (_disposed || busy || recording) return;
    if (noise != null) reduceNoise = noise;
    if (stylusTaps != null) reduceStylusTaps = stylusTaps;
    _notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(noisePreference, reduceNoise);
    await prefs.setBool(tapsPreference, reduceStylusTaps);
  }

  void _queueCleanup(String id) {
    if (_disposed || _cleanupJobs.containsKey(id)) return;
    final original = document.recordings[id];
    if (original == null) return;
    // Capture can restart immediately; cleaning never holds the native-command
    // queue or runs on the pen/sample path. ACK waits for this job separately.
    final future = Future<void>.delayed(Duration.zero, () async {
      try {
        final result = await backend.invoke('cleanSegment', {
          'noteId': document.localId,
          'id': id,
        });
        if (_disposed || !identical(document.recordings[id], original)) return;
        if (result is! Map ||
            result['bytes'] is! Uint8List ||
            result['applied'] != true) {
          cleanupNotice = 'Pulizia non disponibile per un segmento: audio originale conservato.';
          return;
        }
        final bytes = result['bytes'] as Uint8List;
        if (bytes.isEmpty ||
            bytes.length > maxRecordingBytes ||
            totalBytes - original.bytes.length + bytes.length > maxAudioBytes)
          return;
        document.recordings[id] = NoteRecording(id, original.durationMs, bytes);
        onDocumentChanged();
      } catch (_) {
        if (!_disposed) cleanupNotice = 'Pulizia non disponibile per un segmento: audio originale conservato.';
      }
    });
    _cleanupJobs[id] = future;
    unawaited(
      future.whenComplete(() {
        _cleanupJobs.remove(id);
        _notify();
      }),
    );
  }

  Future<void> _waitForCleanup() async {
    await Future.wait(List<Future<void>>.of(_cleanupJobs.values));
  }

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
      backend is! AndroidNoteAudioBackend || (!kIsWeb && nativeAudioAvailable);
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

  Future<void> start() => _run(_startRecording);
  Future<void> _startRecording() async {
    await _settingsReady;
    if (_disposed) return;
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
    recordingId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    await backend.invoke('start', {
      'noteId': document.localId,
      'id': recordingId,
      'reduceNoise': reduceNoise,
      'reduceStylusTaps': reduceStylusTaps,
    });
    if (_disposed) {
      await backend.invoke('release');
      owner = null;
      return;
    }
    _clock.reset();
    _clock.start();
    recording = true;
    listenMode = false;
    onModeChanged();
    _startTimer();
  }

  Future<void> rotateSegment() => _run(() async {
    if (!recording || owner != this) return;
    await _stopRecording();
    if (!_disposed && totalBytes + maxRecordingBytes <= maxAudioBytes)
      await _startRecording();
  });
  Future<void> acknowledge(Iterable<String> ids) async {
    if (!supported || ids.isEmpty) return;
    try {
      await Future.wait([
        for (final id in ids)
          if (_cleanupJobs[id] case final job?) job,
      ]);
      await backend.invoke('ack', {
        'noteId': document.localId,
        'ids': ids.toList(),
      });
    } catch (_) {
      /* Durable staging is intentionally retained if ACK fails. */
    }
  }

  Future<void> recoverStaged() => _run(() async {
    if (!supported) return;
    final raw = await backend.invoke('recover', {'noteId': document.localId});
    if (raw is! List) return;
    var changed = false;
    var partial = false;
    for (final value in raw.whereType<Map>()) {
      var needsCleanup = value['cleanup'] == true;
      if (value['state'] != 'ready') {
        partial = true;
        error = 'Registrazione interrotta non finalizzata: originale conservato per il recupero';
        continue;
      }
      final id = value['id'];
      var bytes = value['bytes'], duration = value['duration'];
      if (id is String &&
          validAudioId(id) &&
          bytes == null &&
          !document.recordings.containsKey(id)) {
        try {
          final segment = await backend.invoke('readSegment', {
            'noteId': document.localId,
            'id': id,
          });
          if (segment is Map) {
            bytes = segment['bytes'];
            duration = segment['duration'];
            needsCleanup = segment['cleanup'] == true;
          }
        } catch (_) {
          error = 'Segmento audio non disponibile: staging conservato';
          continue;
        }
      }
      if (id is! String ||
          !validAudioId(id) ||
          bytes is! Uint8List ||
          bytes.isEmpty ||
          bytes.length > maxRecordingBytes ||
          duration is! int ||
          duration <= 0 ||
          duration > maxRecordingMs ||
          document.recordings.containsKey(id) ||
          totalBytes + bytes.length > maxAudioBytes)
        continue;
      document.recordings[id] = NoteRecording(id, duration, bytes);
      if (needsCleanup) _queueCleanup(id);
      changed = true;
    }
    if (changed) {
      error = partial
          ? 'Segmenti audio recuperati; salvare l’appunto. Registrazione non finalizzata conservata per il recupero.'
          : 'Segmenti audio recuperati; salvare l’appunto';
      onDocumentChanged();
    }
  });
  Future<void> stop() => !recording && !busy && !cleaning
      ? Future.value()
      : _run(() async {
          await _stopRecording();
          await _waitForCleanup();
        });
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
        if (raw['cleanup'] == true) _queueCleanup(id);
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
    await _cleanupJobs[id];
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
