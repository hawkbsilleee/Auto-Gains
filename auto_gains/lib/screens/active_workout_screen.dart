import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../services/rep_detector.dart';
import '../services/arduino_service.dart';
import '../services/workout_store.dart';
import 'workout_summary_screen.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  final List<Exercise> exercises;
  final DetectionMode detectionMode;

  const ActiveWorkoutScreen({
    super.key,
    required this.exercises,
    this.detectionMode = DetectionMode.simulation,
  });

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with SingleTickerProviderStateMixin {
  late final WorkoutSession _session;
  late WorkoutSet _currentSet;
  late RepDetector _repDetector;
  StreamSubscription<RepData>? _repSub;

  int _currentExerciseIndex = 0;
  int _setRepCount = 0;
  double _lastIntensity = 0;

  Timer? _timer;
  Duration _elapsed = Duration.zero;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
    );
    _repDetector = RepDetector(mode: widget.detectionMode);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _startExercise();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed = DateTime.now().difference(_session.startTime);
      });
    });
  }

  void _startExercise() {
    _repDetector.stop();
    _repSub?.cancel();
    _setRepCount = 0;
    _lastIntensity = 0;

    final setsForExercise = _session.sets
        .where((s) => s.exercise == widget.exercises[_currentExerciseIndex])
        .length;

    _currentSet = WorkoutSet(
      exercise: widget.exercises[_currentExerciseIndex],
      startTime: DateTime.now(),
      setNumber: setsForExercise + 1,
    );

    _repDetector = RepDetector(mode: widget.detectionMode);
    _repDetector.start();
    _repSub = _repDetector.repStream.listen(_onRep);
  }

  void _onRep(RepData rep) {
    if (!mounted) return;
    setState(() {
      _setRepCount++;
      _lastIntensity = rep.intensity;
      _currentSet.reps.add(rep);
    });
    _pulseController.forward().then((_) {
      if (mounted) _pulseController.reverse();
    });
  }

  void _nextSet() {
    _repDetector.stop();
    _repSub?.cancel();
    _currentSet.endTime = DateTime.now();
    if (_currentSet.reps.isNotEmpty) {
      _session.sets.add(_currentSet);
    }
    setState(() {});
    _startExercise();
  }

  void _nextExercise() {
    _repDetector.stop();
    _repSub?.cancel();
    _currentSet.endTime = DateTime.now();
    if (_currentSet.reps.isNotEmpty) {
      _session.sets.add(_currentSet);
    }
    if (_currentExerciseIndex + 1 >= widget.exercises.length) {
      _finishWorkout();
      return;
    }
    setState(() {
      _currentExerciseIndex++;
    });
    _startExercise();
  }

  void _finishWorkout() {
    _repDetector.stop();
    _repSub?.cancel();
    _timer?.cancel();
    _currentSet.endTime = DateTime.now();
    if (_currentSet.reps.isNotEmpty) {
      _session.sets.add(_currentSet);
    }
    _session.endTime = DateTime.now();
    WorkoutStore.instance.add(_session);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutSummaryScreen(session: _session),
      ),
    );
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Workout?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Your progress so far will be saved.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finishWorkout();
            },
            child: const Text('End', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _repDetector.dispose();
    _repSub?.cancel();
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Color _intensityColor(double v) {
    if (v > 0.8) return AppColors.error;
    if (v > 0.6) return AppColors.accent;
    return AppColors.primary;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercises[_currentExerciseIndex];
    final isLast = _currentExerciseIndex >= widget.exercises.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Top bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.name,
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Set ${_currentSet.setNumber}',
                            style: TextStyle(
                              fontSize: 15,
                              color: exercise.primaryMuscle.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined,
                                  size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                _fmt(_elapsed),
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.detectionMode == DetectionMode.arduino &&
                            _repDetector.connectionState != null)
                          StreamBuilder<ArduinoConnectionState>(
                            stream: _repDetector.connectionState,
                            builder: (context, snapshot) {
                              final state = snapshot.data ??
                                  ArduinoConnectionState.disconnected;
                              final color = switch (state) {
                                ArduinoConnectionState.connected =>
                                  AppColors.primary,
                                ArduinoConnectionState.connecting =>
                                  AppColors.accent,
                                ArduinoConnectionState.error => AppColors.error,
                                ArduinoConnectionState.disconnected =>
                                  AppColors.textTertiary,
                              };
                              final label = switch (state) {
                                ArduinoConnectionState.connected => 'IMU',
                                ArduinoConnectionState.connecting => '...',
                                ArduinoConnectionState.error => 'ERR',
                                ArduinoConnectionState.disconnected => 'OFF',
                              };
                              return Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),

                const Spacer(flex: 2),

                // Rep counter
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Column(
                    children: [
                      Text(
                        '$_setRepCount',
                        style: GoogleFonts.inter(
                          fontSize: 96,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'REPS',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Intensity bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Intensity',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary)),
                          Text(
                            '${(_lastIntensity * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _intensityColor(_lastIntensity),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _lastIntensity,
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceLight,
                          color: _intensityColor(_lastIntensity),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Metrics row
                Row(
                  children: [
                    _miniMetric(
                      'Avg Intensity',
                      '${(_currentSet.averageIntensity * 100).toInt()}%',
                      AppColors.secondary,
                    ),
                    _miniMetric(
                      'Peak',
                      '${(_currentSet.peakIntensity * 100).toInt()}%',
                      AppColors.accent,
                    ),
                    _miniMetric(
                      'Exercise',
                      '${_currentExerciseIndex + 1}/${widget.exercises.length}',
                      AppColors.textSecondary,
                    ),
                  ],
                ),

                const Spacer(flex: 3),

                // Controls
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _nextSet,
                        child: const Text('Next Set'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: isLast
                          ? ElevatedButton(
                              onPressed: _finishWorkout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.background,
                              ),
                              child: const Text('Finish'),
                            )
                          : ElevatedButton(
                              onPressed: _nextExercise,
                              child: const Text('Next Exercise'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _confirmEnd,
                  child: const Text(
                    'End Workout',
                    style: TextStyle(color: AppColors.error, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
