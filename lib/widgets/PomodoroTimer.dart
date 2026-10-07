import 'package:xournalpp/src/app_appearance.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';

/// Le tre fasi del ciclo Pomodoro.
enum PomodoroPhase { work, shortBreak, longBreak }

/// Mini-timer Pomodoro a comparsa, mostrato sopra il canvas.
///
/// Correzioni e miglioramenti rispetto alla versione precedente:
/// - Conteggio basato su un ISTANTE DI FINE ([_endAt]) e non su un tick al
///   secondo: resta preciso anche se Flutter rallenta i frame o l'app va in
///   background (al rientro il tempo residuo viene ricalcolato).
/// - Le durate, i cicli e l'avvio automatico vengono SALVATI in
///   SharedPreferences e ripristinati alla prossima apertura.
/// - "Salta" avanza di fase in silenzio; suono e vibrazione partono solo al
///   completamento naturale della fase.
/// - I puntini dei cicli si azzerano correttamente dopo la pausa lunga.
/// - Estetica "Nothing OS": anello a matrice di punti, tempo in font
///   dot-matrix, pannello nero con bordo sottile.
class PomodoroTimer extends StatefulWidget {
  final VoidCallback? onClose;
  final void Function(PomodoroPhase finished, PomodoroPhase next)?
  onPhaseComplete;

  const PomodoroTimer({Key? key, this.onClose, this.onPhaseComplete})
    : super(key: key);

  @override
  State<PomodoroTimer> createState() => _PomodoroTimerState();
}

class _PomodoroTimerState extends State<PomodoroTimer>
    with WidgetsBindingObserver {
  // Impostazioni (persistite)
  int workMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int cyclesBeforeLongBreak = 4;
  bool autoStartNext = false;

  static const String _kWork = 'pomodoro_work_min';
  static const String _kShort = 'pomodoro_short_min';
  static const String _kLong = 'pomodoro_long_min';
  static const String _kCycles = 'pomodoro_cycles';
  static const String _kAuto = 'pomodoro_autostart';

  // Stato del ciclo
  PomodoroPhase _phase = PomodoroPhase.work;
  int _completedWorkSessions = 0;
  bool _showSettings = false;

  // Motore del tempo: quando gira, la verita' e' _endAt; da fermo, _remaining.
  DateTime? _endAt;
  late Duration _remaining;
  Timer? _ticker;

  bool get _running => _endAt != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remaining = _phaseDuration(_phase);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  // Al rientro dal background ricalcoliamo il residuo dall'orologio reale.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running) {
      final left = _endAt!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _completePhase();
      } else {
        setState(() => _remaining = left);
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        workMinutes = prefs.getInt(_kWork) ?? workMinutes;
        shortBreakMinutes = prefs.getInt(_kShort) ?? shortBreakMinutes;
        longBreakMinutes = prefs.getInt(_kLong) ?? longBreakMinutes;
        cyclesBeforeLongBreak = prefs.getInt(_kCycles) ?? cyclesBeforeLongBreak;
        autoStartNext = prefs.getBool(_kAuto) ?? autoStartNext;
        if (!_running) _remaining = _phaseDuration(_phase);
      });
    } catch (_) {}
  }

  Future<void> _persistSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kWork, workMinutes);
      await prefs.setInt(_kShort, shortBreakMinutes);
      await prefs.setInt(_kLong, longBreakMinutes);
      await prefs.setInt(_kCycles, cyclesBeforeLongBreak);
      await prefs.setBool(_kAuto, autoStartNext);
    } catch (_) {}
  }

  Duration _phaseDuration(PomodoroPhase phase) {
    switch (phase) {
      case PomodoroPhase.work:
        return Duration(minutes: workMinutes);
      case PomodoroPhase.shortBreak:
        return Duration(minutes: shortBreakMinutes);
      case PomodoroPhase.longBreak:
        return Duration(minutes: longBreakMinutes);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_running) return;
      final left = _endAt!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _completePhase();
      } else if (left.inSeconds != _remaining.inSeconds) {
        setState(() => _remaining = left);
      }
    });
  }

  void _start() {
    if (_running) return;
    setState(() => _endAt = DateTime.now().add(_remaining));
    _startTicker();
  }

  void _pause() {
    if (!_running) return;
    _ticker?.cancel();
    setState(() {
      _remaining = _endAt!.difference(DateTime.now());
      if (_remaining < Duration.zero) _remaining = Duration.zero;
      _endAt = null;
    });
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _endAt = null;
      _remaining = _phaseDuration(_phase);
    });
  }

  /// Avanza alla fase successiva. [manual] = premuto "salta": niente suoni.
  void _completePhase({bool manual = false}) {
    _ticker?.cancel();
    final finished = _phase;
    final PomodoroPhase next;
    int completed = _completedWorkSessions;
    if (finished == PomodoroPhase.work) {
      completed += 1;
      next = (completed % cyclesBeforeLongBreak == 0)
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
    } else {
      next = PomodoroPhase.work;
    }

    final bool startNow = !manual && autoStartNext;
    setState(() {
      _completedWorkSessions = completed;
      _phase = next;
      _remaining = _phaseDuration(next);
      _endAt = startNow ? DateTime.now().add(_remaining) : null;
    });
    if (startNow) _startTicker();

    if (!manual) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      widget.onPhaseComplete?.call(finished, next);
    }
  }

  void _applyDurations() {
    if (!_running) {
      setState(() => _remaining = _phaseDuration(_phase));
    }
    _persistSettings();
  }

  String get _timeString {
    final int totalSeconds = _remaining.inSeconds.clamp(0, 99 * 3600);
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _phaseLabel {
    switch (_phase) {
      case PomodoroPhase.work:
        return 'CONCENTRAZIONE';
      case PomodoroPhase.shortBreak:
        return 'PAUSA BREVE';
      case PomodoroPhase.longBreak:
        return 'PAUSA LUNGA';
    }
  }

  Color get _accent {
    switch (_phase) {
      case PomodoroPhase.work:
        return Theme.of(context).colorScheme.primary; // accento globale
      case PomodoroPhase.shortBreak:
        return const Color(0xFF26A69A);
      case PomodoroPhase.longBreak:
        return const Color(0xFF1E88E5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _phaseDuration(_phase).inSeconds;
    final progress = total == 0
        ? 0.0
        : (1 - (_remaining.inSeconds / total)).clamp(0.0, 1.0);
    final accent = _accent;
    final icons = context.watch<ThemeController>().icons;

    // Puntini del ciclo: quante sessioni di lavoro completate nel giro attuale.
    // Durante la pausa lunga il giro e' completo (tutti accesi); dopo, riparte da 0.
    int filledDots = _completedWorkSessions % cyclesBeforeLongBreak;
    if (_phase == PomodoroPhase.longBreak) filledDots = cyclesBeforeLongBreak;

    final TextStyle timeStyle =
        (Theme.of(context).textTheme.displaySmall ?? const TextStyle())
            .copyWith(color: Colors.white, fontSize: 38);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 252,
          padding: const EdgeInsets.all(16),
          decoration: const ShapeDecoration(
            color: AppAppearance.panel,
            shape: AppAppearance.panelShape,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'POMODORO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showSettings = !_showSettings),
                    child: Icon(
                      icons.tune,
                      color: _showSettings ? accent : Colors.white70,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: widget.onClose,
                    child: Icon(icons.close, color: Colors.white70, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _phaseLabel,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 118,
                      width: 118,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _DotRingPainter(
                            progress: progress,
                            accent: accent,
                            base: Colors.white12,
                          ),
                        ),
                      ),
                    ),
                    Text(_timeString, style: timeStyle),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(cyclesBeforeLongBreak, (i) {
                  final done = i < filledDots;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? accent : Colors.white24,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _circleButton(
                    icon: _running ? icons.pause : icons.play,
                    color: accent,
                    onTap: _running ? _pause : _start,
                  ),
                  _circleButton(
                    icon: icons.reset,
                    color: Colors.white24,
                    onTap: _reset,
                  ),
                  _circleButton(
                    icon: icons.skip,
                    color: Colors.white24,
                    onTap: () => _completePhase(manual: true),
                  ),
                ],
              ),
              if (_showSettings) ...[
                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade800),
                _durationRow(
                  'Lavoro',
                  workMinutes,
                  (v) {
                    setState(() => workMinutes = v);
                    _applyDurations();
                  },
                  min: 1,
                  max: 90,
                ),
                _durationRow(
                  'Pausa breve',
                  shortBreakMinutes,
                  (v) {
                    setState(() => shortBreakMinutes = v);
                    _applyDurations();
                  },
                  min: 1,
                  max: 30,
                ),
                _durationRow(
                  'Pausa lunga',
                  longBreakMinutes,
                  (v) {
                    setState(() => longBreakMinutes = v);
                    _applyDurations();
                  },
                  min: 1,
                  max: 60,
                ),
                _durationRow(
                  'Cicli',
                  cyclesBeforeLongBreak,
                  (v) {
                    setState(() => cyclesBeforeLongBreak = v);
                    _persistSettings();
                  },
                  min: 1,
                  max: 8,
                  suffix: '',
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Avvio automatico',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: autoStartNext,
                        activeColor: accent,
                        onChanged: (v) {
                          setState(() => autoStartNext = v);
                          _persistSettings();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _durationRow(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    required int min,
    required int max,
    String suffix = ' min',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          InkWell(
            onTap: value > min ? () => onChanged(value - 1) : null,
            child: Icon(
              Icons.remove_circle_outline,
              color: value > min ? Colors.white : Colors.white24,
              size: 20,
            ),
          ),
          Container(
            width: 46,
            alignment: Alignment.center,
            child: Text(
              '$value$suffix',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          InkWell(
            onTap: value < max ? () => onChanged(value + 1) : null,
            child: Icon(
              Icons.add_circle_outline,
              color: value < max ? Colors.white : Colors.white24,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Anello di avanzamento a "matrice di punti" in stile Nothing.
class _DotRingPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color base;

  _DotRingPainter({
    required this.progress,
    required this.accent,
    required this.base,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int dots = 48;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final int lit = (progress * dots).round();

    final paint = Paint();
    for (int i = 0; i < dots; i++) {
      // Si parte dall'alto (ore 12) e si gira in senso orario.
      final angle = -math.pi / 2 + 2 * math.pi * i / dots;
      final pos =
          center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      final bool on = i < lit;
      paint.color = on ? accent : base;
      canvas.drawCircle(pos, on ? 2.6 : 1.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotRingPainter old) =>
      (old.progress * 48).round() != (progress * 48).round() ||
      old.accent != accent ||
      old.base != base;
}
