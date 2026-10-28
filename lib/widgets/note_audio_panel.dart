import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/note_audio_controller.dart';

String audioTime(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class NoteAudioButton extends StatelessWidget {
  final NoteAudioController audio;
  const NoteAudioButton({super.key, required this.audio});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: audio,
    builder: (context, _) => IconButton(
      tooltip: audio.recording ? 'Registrazione in corso' : 'Audio appunto',
      icon: Icon(
        audio.recording ? Icons.mic : Icons.mic_none,
        color: audio.recording ? Colors.redAccent : null,
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => NoteAudioPanel(audio: audio),
      ),
    ),
  );
}

class NoteAudioPanel extends StatefulWidget {
  final NoteAudioController audio;
  const NoteAudioPanel({super.key, required this.audio});
  @override
  State<NoteAudioPanel> createState() => _NoteAudioPanelState();
}

class _NoteAudioPanelState extends State<NoteAudioPanel> {
  NoteAudioController get audio => widget.audio;
  int? _dragMs;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([audio, audio.cursor]),
    builder: (context, _) {
      final cursor = audio.cursor.value;
      final selected = audio.document.recordings[cursor.id];
      final recordings = audio.document.recordings.values.toList();
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Audio appunto',
                        style: TextStyle(fontSize: 22),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Chiudi pannello',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  'Registra mentre scrivi. Durante l’ascolto il tratto viene evidenziato nel momento in cui è stato scritto.',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const ValueKey('audio-noise-reduction'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Riduzione rumore delicata'),
                  subtitle: const Text(
                    'Attenua rimbombi e fruscio nelle pause, con un filtro leggero per la voce distante.',
                  ),
                  value: audio.reduceNoise,
                  onChanged: !audio.supported || audio.recording || audio.busy
                      ? null
                      : (value) =>
                            unawaited(audio.setCleanupSettings(noise: value)),
                ),
                SwitchListTile(
                  key: const ValueKey('audio-stylus-tap-reduction'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Attenua i colpi della penna'),
                  subtitle: const Text(
                    'Riduce i brevi “tac” vicini ai contatti sullo schermo, senza tagliare intervalli audio.',
                  ),
                  value: audio.reduceStylusTaps,
                  onChanged: !audio.supported || audio.recording || audio.busy
                      ? null
                      : (value) => unawaited(
                          audio.setCleanupSettings(stylusTaps: value),
                        ),
                ),
                const Text(
                  'Le opzioni valgono per le nuove registrazioni.',
                  style: TextStyle(fontSize: 12),
                ),
                if (audio.cleaning) const Text('Pulizia audio in background…'),
                if (audio.cleanupNotice != null)
                  Text(
                    audio.cleanupNotice!,
                    style: const TextStyle(fontSize: 12),
                  ),
                FilledButton.icon(
                  onPressed: !audio.supported || audio.busy
                      ? null
                      : () => unawaited(
                          audio.recording ? audio.stop() : audio.start(),
                        ),
                  icon: Icon(audio.recording ? Icons.stop : Icons.mic),
                  label: Text(
                    audio.recording
                        ? 'Ferma registrazione · ${audioTime(audio.elapsedMs)}'
                        : 'Registra audio',
                  ),
                ),
                if (!audio.supported)
                  const Text('Audio disponibile nella versione Android.'),
                if (audio.busy) const LinearProgressIndicator(),
                if (audio.error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      audio.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (recordings.isEmpty && !audio.recording)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Nessuna registrazione in questo appunto.'),
                  ),
                if (recordings.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .25,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: recordings.length,
                      itemBuilder: (context, i) {
                        final r = recordings[i];
                        return ListTile(
                          selected: r.id == cursor.id,
                          leading: const Icon(Icons.audiotrack),
                          title: Text('Registrazione ${i + 1}'),
                          subtitle: Text(audioTime(r.durationMs)),
                          trailing: IconButton(
                            tooltip: 'Ascolta registrazione ${i + 1}',
                            icon: const Icon(Icons.play_arrow),
                            onPressed:
                                audio.busy ||
                                    audio.recording ||
                                    !audio.supported
                                ? null
                                : () => unawaited(audio.play(r.id)),
                          ),
                        );
                      },
                    ),
                  ),
                if (selected != null)
                  Row(
                    children: [
                      IconButton(
                        tooltip: cursor.playing ? 'Pausa' : 'Riprendi',
                        icon: Icon(
                          cursor.playing ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: audio.busy
                            ? null
                            : () => unawaited(audio.pauseOrResume()),
                      ),
                      IconButton(
                        tooltip: 'Ferma ascolto',
                        icon: const Icon(Icons.stop),
                        onPressed: audio.busy
                            ? null
                            : () => unawaited(audio.stopPlayback()),
                      ),
                      Expanded(
                        child: Slider(
                          value: (_dragMs ?? cursor.milliseconds)
                              .toDouble()
                              .clamp(0, selected.durationMs.toDouble()),
                          max: selected.durationMs.toDouble(),
                          label: audioTime(cursor.milliseconds),
                          onChanged: audio.busy
                              ? null
                              : (v) => setState(() => _dragMs = v.round()),
                          onChangeEnd: audio.busy
                              ? null
                              : (v) {
                                  setState(() => _dragMs = null);
                                  unawaited(audio.seek(v.round()));
                                },
                        ),
                      ),
                      Text(
                        '${audioTime(_dragMs ?? cursor.milliseconds)} / ${audioTime(selected.durationMs)}',
                      ),
                    ],
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ascolta dal tratto'),
                  subtitle: const Text(
                    'Chiudi il pannello e tocca un tratto con la penna per ascoltare da quel punto. Selezionare uno strumento torna alla scrittura.',
                  ),
                  value: audio.listenMode,
                  onChanged:
                      audio.recording ||
                          audio.busy ||
                          !audio.supported ||
                          recordings.isEmpty
                      ? null
                      : audio.setListenMode,
                ),
                const Text(
                  'Il microfono si ferma salvando o lasciando l’app. Massimo 120 minuti e 48 MB per registrazione, 128 MB per appunto.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
