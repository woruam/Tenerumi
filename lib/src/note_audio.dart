import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

const maxAudioBytes = 128 * 1024 * 1024;
const maxRecordingBytes = 48 * 1024 * 1024;
const maxRecordingMs = 120 * 60 * 1000;
bool validAudioId(String id) => RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id);

/// Immutable metadata; snapshots share compressed bytes, never decoded samples.
class NoteRecording {
  final String id;
  final int durationMs;
  final Uint8List bytes;
  NoteRecording(this.id, this.durationMs, Uint8List data)
    : bytes = data.asUnmodifiableView();
  XmlElement toXml() => XmlElement(
    XmlName('osipp-audio'),
    [
      XmlAttribute(XmlName('id'), id),
      XmlAttribute(XmlName('duration-ms'), '$durationMs'),
    ],
    [XmlText(base64Encode(bytes))],
  );
  static Map<String, NoteRecording> decode(Iterable<XmlElement> elements) {
    final result = <String, NoteRecording>{};
    var total = 0;
    for (final e in elements) {
      final id = e.getAttribute('id') ?? '';
      final duration = int.tryParse(e.getAttribute('duration-ms') ?? '') ?? 0;
      final encoded = e.innerText.trim();
      if (!validAudioId(id) ||
          duration <= 0 ||
          duration > maxRecordingMs + 5000 ||
          encoded.length > (maxAudioBytes - total) * 4 ~/ 3 + 4 ||
          encoded.length > maxRecordingBytes * 4 ~/ 3 + 4)
        continue;
      try {
        final data = base64Decode(encoded);
        if (data.isEmpty ||
            data.length > maxRecordingBytes ||
            total + data.length > maxAudioBytes ||
            result.containsKey(id))
          continue;
        total += data.length;
        result[id] = NoteRecording(id, duration, data);
      } on FormatException {
        /* Invalid optional audio must not lose the note. */
      }
    }
    return result;
  }
}

class StrokeAudioLink {
  final String recordingId;
  final int startMs, endMs;
  final List<int> samples;
  StrokeAudioLink(
    this.recordingId,
    this.startMs,
    this.endMs, [
    List<int> times = const [],
  ]) : samples = List.unmodifiable(times);
  List<XmlAttribute> get attributes => [
    XmlAttribute(XmlName('osipp-audio-id'), recordingId),
    XmlAttribute(XmlName('osipp-audio-start'), '$startMs'),
    XmlAttribute(XmlName('osipp-audio-end'), '$endMs'),
    if (samples.isNotEmpty)
      XmlAttribute(XmlName('osipp-audio-times'), samples.join(' ')),
  ];
  static StrokeAudioLink? decode(XmlElement e, int pointCount) {
    final id = e.getAttribute('osipp-audio-id') ?? '';
    final start = int.tryParse(e.getAttribute('osipp-audio-start') ?? '');
    final end = int.tryParse(e.getAttribute('osipp-audio-end') ?? '');
    if (!validAudioId(id) ||
        start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        end > maxRecordingMs + 5000)
      return null;
    final times = <int>[];
    final raw = e.getAttribute('osipp-audio-times') ?? '';
    if (raw.length <= pointCount * 9 + 1 && raw.isNotEmpty) {
      for (final value in raw.split(' ')) {
        final t = int.tryParse(value);
        if (t == null || t < (times.isEmpty ? start : times.last) || t > end) {
          times.clear();
          break;
        }
        times.add(t);
      }
    }
    return StrokeAudioLink(
      id,
      start,
      end,
      times.length == pointCount ? times : const [],
    );
  }
}
