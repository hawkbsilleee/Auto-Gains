import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibration/vibration.dart';
import '../theme/app_theme.dart';
import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../data/exercise_library.dart';
import '../config/backend_config.dart';
import '../services/rep_detector.dart';
import '../services/arduino_service.dart';
import '../services/workout_store.dart';
import 'workout_summary_screen.dart';
import '../widgets/speed_guide.dart';
import '../widgets/pace_timeline.dart';
import '../widgets/weight_input_dialog.dart';

// Configurable rest timer settings
const Duration kSetCompletionDuration = Duration(seconds: 10); // Time before set ends
const Duration kMaxRestDuration = Duration(seconds: 120); // Time before rest warning
const Duration kRestCheckInterval = Duration(seconds: 1); // Check frequently

const _autoDetectPlaceholder = Exercise(
  id: 'auto_detect',
  name: 'Detecting...',
  primaryMuscle: MuscleGroup.fullBody,
  description: '',
);

class ActiveWorkoutScreen extends StatefulWidget {
  final List<Exercise> exercises;
  final DetectionMode detectionMode;
  /// When true, connects to backend and runs exercise classification automatically.
  final bool autoDetect;

  const ActiveWorkoutScreen({
    super.key,
    required this.exercises,
    this.detectionMode = DetectionMode.simulation,
    this.autoDetect = false,
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
  StreamSubscription<double>? _speedSub;

  /// Mutable exercise list — starts with placeholder for auto-detect, otherwise copies widget.exercises.
  late List<Exercise> _exercises;

  int _currentExerciseIndex = 0;
  int _setRepCount = 0;
  double _speedDeviation = 0;
  double? _currentWeight; // Current weight for the set

  // Pace tracking
  final List<double> _paceHistory = [];

  // Activity state from backend
  bool _isActive = false;
  StreamSubscription<bool>? _activeStateSub;

  // Set detection
  StreamSubscription<int>? _setDetectedSub;

  Timer? _timer;
  Duration _elapsed = Duration.zero;

  // Countdown
  int _countdownValue = 3;
  Timer? _countdownTimer;
  bool get _isCountingDown => _countdownValue > 0;

  // Rest timer
  DateTime? _lastSetCompletionTime;
  DateTime? _lastRepTime;
  Timer? _restCheckTimer;
  bool _showRestWarning = false;

  // Auto-detect state
  bool _isAutoDetecting = false;
  ArduinoService? _ownedArduinoService;
  StreamSubscription<AutoDetectResult>? _autoDetectSub;
  StreamSubscription<ArduinoConnectionState>? _connectionSub;
  bool _autoDetectTriggered = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Build mutable exercise list
    if (widget.autoDetect) {
      _exercises = [_autoDetectPlaceholder];
      _isAutoDetecting = true;
    } else {
      _exercises = List.of(widget.exercises);
    }

    _session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
    );

    // For auto-detect, create ArduinoService and pass to RepDetector
    if (widget.autoDetect) {
      _ownedArduinoService = ArduinoService(wsUrl: kBackendWsUrl);
      _repDetector = RepDetector(
        mode: DetectionMode.arduino,
        existingArduinoService: _ownedArduinoService,
      );

      // Listen for exercise detection result
      _autoDetectSub = _ownedArduinoService!.exerciseDetectedStream.listen((result) {
        if (!mounted) return;
        final exercise = exerciseFromClassifierLabel(result.exercise);
        setState(() {
          _isAutoDetecting = false;
          if (exercise != null) {
            _exercises[0] = exercise;
            _currentSet.exercise = exercise;
          } else {
            // Unknown label — use a fallback
            final fallback = Exercise(
              id: 'unknown',
              name: result.exercise,
              primaryMuscle: MuscleGroup.fullBody,
              description: 'Auto-detected exercise',
            );
            _exercises[0] = fallback;
            _currentSet.exercise = fallback;
          }
        });
      });

      // Listen for connection state to trigger auto-detect once connected
      _connectionSub = _ownedArduinoService!.connectionState.listen((state) {
        if (state == ArduinoConnectionState.connected && !_autoDetectTriggered) {
          _autoDetectTriggered = true;
          _ownedArduinoService!.startAutoDetect();
        }
      });

      _ownedArduinoService!.connect();
    } else {
      _repDetector = RepDetector(
        mode: widget.detectionMode,
        existingArduinoService: null,
      );
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Pre-initialize the current set so build() can reference it during countdown
    _currentSet = WorkoutSet(
      exercise: _exercises[_currentExerciseIndex],
      startTime: DateTime.now(),
      setNumber: 1,
    );

    // Schedule weight dialog to show after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoDetect) {
        _promptForWeightThenAutoDetect();
      } else {
        _promptForWeightThenStart();
      }
    });
  }

  Future<void> _promptForWeightThenAutoDetect() async {
    // Show weight input dialog
    final weight = await showDialog<double?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WeightInputDialog(
        exerciseName: 'Auto-Detect Workout',
        previousWeight: _currentWeight,
      ),
    );

    if (!mounted) return;

    _currentWeight = weight;
    // Skip countdown for auto-detect — user is already exercising
    _countdownValue = 0;
    _startExercise();
    _startTimer();
  }

  Future<void> _promptForWeightThenStart() async {
    // Show weight input dialog
    final weight = await showDialog<double?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WeightInputDialog(
        exerciseName: _exercises[_currentExerciseIndex].name,
        previousWeight: _currentWeight,
      ),
    );

    if (!mounted) return;

    _currentWeight = weight;
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownValue--;
      });
      if (_countdownValue <= 0) {
        timer.cancel();
        _startExercise();
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed = DateTime.now().difference(_session.startTime);
      });
    });
    _startRestCheckTimer();
  }

  void _startRestCheckTimer() {
    _restCheckTimer = Timer.periodic(kRestCheckInterval, (_) {
      if (_lastRepTime == null) return;

      final timeSinceLastRep = DateTime.now().difference(_lastRepTime!);

      // First check: Has enough time passed to end the set?
      if (timeSinceLastRep >= kSetCompletionDuration &&
          _currentSet.reps.isNotEmpty &&
          _lastSetCompletionTime == null) {
        // End the current set
        _completeCurrentSet();
      }

      // Second check: Has rest been too long? (show warning)
      final lastActivityTime = _lastSetCompletionTime ?? _lastRepTime;
      if (lastActivityTime != null) {
        final restDuration = DateTime.now().difference(lastActivityTime);
        if (restDuration > kMaxRestDuration && !_showRestWarning) {
          _triggerRestWarning();
        }
      }
    });
  }

  void _triggerRestWarning() {
    if (!mounted) return;
    setState(() {
      _showRestWarning = true;
    });
    // Strong vibration pattern - 500ms vibrate, 200ms pause, 500ms vibrate
    // Pattern: [delay before start, vibrate, pause, vibrate]
    // Intensities: max strength (255) for each vibration
    Vibration.vibrate(
      pattern: [0, 500, 200, 500],
      intensities: [0, 255, 0, 255],
    );
    // Optionally dismiss after a few seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showRestWarning = false;
        });
      }
    });
  }

  void _startExercise() {
    _repDetector.stop();
    _repSub?.cancel();
    _speedSub?.cancel();
    _activeStateSub?.cancel();
    _setDetectedSub?.cancel();
    _setRepCount = 0;
    _speedDeviation = 0;
    _paceHistory.clear();
    _isActive = false;

    final setsForExercise = _session.sets
        .where((s) => s.exercise == _exercises[_currentExerciseIndex])
        .length;

    _currentSet = WorkoutSet(
      exercise: _exercises[_currentExerciseIndex],
      startTime: DateTime.now(),
      setNumber: setsForExercise + 1,
      weight: _currentWeight,
    );

    _repDetector.start();
    _repSub = _repDetector.repStream.listen(_onRep);

    // Subscribe to speed stream (arduino mode only)
    final speed = _repDetector.speedStream;
    if (speed != null) {
      _speedSub = speed.listen((deviation) {
        if (mounted) {
          setState(() => _speedDeviation = deviation);
          if (_isActive) {
            _paceHistory.add(deviation);
          }
        }
      });
    }

    // Subscribe to active state stream (arduino mode only)
    final activeStream = _repDetector.activeStateStream;
    if (activeStream != null) {
      _activeStateSub = activeStream.listen((active) {
        if (mounted) setState(() => _isActive = active);
      });
    }

    // Subscribe to set detection stream (arduino mode only)
    final setStream = _repDetector.setDetectedStream;
    if (setStream != null) {
      print('[flutter] Subscribing to set boundary stream...');
      _setDetectedSub = setStream.listen(_onSetBoundary);
      print('[flutter] Set boundary subscription active!');
    } else {
      print('[flutter] WARNING: setDetectedStream is null - not subscribing!');
    }
  }

  void _onRep(RepData rep) {
    if (!mounted) return;
    print('[flutter] UI received rep: setRepCount=${_setRepCount + 1}');
    setState(() {
      _setRepCount++;
      _currentSet.reps.add(rep);
      // Track last rep time for rest timer and set completion
      _lastRepTime = DateTime.now();
      _lastSetCompletionTime = null; // Reset so we can detect next set completion
      _showRestWarning = false; // Dismiss warning when user resumes activity
    });
    _pulseController.forward().then((_) {
      if (mounted) _pulseController.reverse();
    });
  }

  void _completeCurrentSet() {
    if (!mounted || _currentSet.reps.isEmpty) return;

    final completedSetNumber = _currentSet.setNumber;
    final completedReps = _currentSet.reps.length;

    // Save current set with pace data
    _currentSet.endTime = DateTime.now();
    _currentSet.paceDeviations.addAll(_paceHistory);
    _session.sets.add(_currentSet);

    // Track rest timer - prioritize set completion time for rest tracking between sets
    _lastSetCompletionTime = DateTime.now();
    _lastRepTime = null; // Clear rep time so rest tracking uses set completion
    _showRestWarning = false;

    // Clear pace history for the new set
    _paceHistory.clear();

    // Start a new set for the same exercise
    final setsForExercise = _session.sets
        .where((s) => s.exercise == _exercises[_currentExerciseIndex])
        .length;

    setState(() {
      _currentSet = WorkoutSet(
        exercise: _exercises[_currentExerciseIndex],
        startTime: DateTime.now(),
        setNumber: setsForExercise + 1,
        weight: _currentWeight,
      );
      _setRepCount = 0;
    });

    // Haptic feedback
    Vibration.vibrate(duration: 150);

    // Visual feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Set $completedSetNumber complete — $completedReps reps',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: AppColors.background,
            ),
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _onSetBoundary(int repCountAtBoundary) {
    // Backend-triggered set boundary (if using Arduino mode with backend detection)
    _completeCurrentSet();
  }

  void _finishWorkout() {
    _repDetector.stop();
    _repSub?.cancel();
    _speedSub?.cancel();
    _activeStateSub?.cancel();
    _setDetectedSub?.cancel();
    _timer?.cancel();
    _currentSet.endTime = DateTime.now();
    _currentSet.paceDeviations.addAll(_paceHistory);
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

  Future<void> _editWeight() async {
    final newWeight = await showDialog<double?>(
      context: context,
      builder: (context) => WeightInputDialog(
        exerciseName: _exercises[_currentExerciseIndex].name,
        previousWeight: _currentWeight,
      ),
    );

    if (!mounted) return;

    if (newWeight != null) {
      setState(() {
        _currentWeight = newWeight;
        // Save existing reps and pace data
        final existingReps = List<RepData>.from(_currentSet.reps);
        final existingPace = List<double>.from(_currentSet.paceDeviations);

        // Create new set with updated weight
        _currentSet = WorkoutSet(
          exercise: _currentSet.exercise,
          startTime: _currentSet.startTime,
          setNumber: _currentSet.setNumber,
          weight: newWeight,
        );

        // Restore the existing reps and pace data
        _currentSet.reps.addAll(existingReps);
        _currentSet.paceDeviations.addAll(existingPace);
      });
    }
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
    _speedSub?.cancel();
    _activeStateSub?.cancel();
    _setDetectedSub?.cancel();
    _timer?.cancel();
    _countdownTimer?.cancel();
    _restCheckTimer?.cancel();
    _pulseController.dispose();
    _autoDetectSub?.cancel();
    _connectionSub?.cancel();
    _ownedArduinoService?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercises[_currentExerciseIndex];
    final effectiveMode = widget.autoDetect ? DetectionMode.arduino : widget.detectionMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
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
                          // Exercise name — show detecting state or real name
                          if (_isAutoDetecting)
                            Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Detecting...',
                                  style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              exercise.name,
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'Set ${_currentSet.setNumber}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _isAutoDetecting
                                      ? AppColors.textSecondary
                                      : exercise.primaryMuscle.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_currentWeight != null) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _editWeight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${_currentWeight!.toStringAsFixed(0)} lbs',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.edit,
                                          size: 12,
                                          color: AppColors.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                        if (effectiveMode == DetectionMode.arduino &&
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
                                ArduinoConnectionState.error => 'No connection',
                                ArduinoConnectionState.disconnected => 'OFF',
                              };
                              final isError = state == ArduinoConnectionState.error;
                              return Tooltip(
                                message: isError
                                    ? 'Backend not reachable. Start: python backend/ws_server.py --mock. Then tap to retry.'
                                    : (state == ArduinoConnectionState.connected
                                        ? 'IMU connected'
                                        : state == ArduinoConnectionState.connecting
                                            ? 'Connecting...'
                                            : 'IMU off'),
                                child: GestureDetector(
                                  onTap: isError
                                      ? () {
                                          _repDetector.reconnectArduino();
                                        }
                                      : null,
                                  child: Container(
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
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),

                const Spacer(flex: 2),

                // Rep counter (smaller)
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Column(
                    children: [
                      Text(
                        '$_setRepCount',
                        style: GoogleFonts.inter(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'REPS',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Speed / tempo guide (bigger)
                SpeedGuideWidget(
                  simulate: effectiveMode != DetectionMode.arduino,
                  speedDeviation: _speedDeviation,
                  active: effectiveMode != DetectionMode.arduino || _isActive,
                  scale: 1.4,
                ),

                const SizedBox(height: 20),

                // Pace timeline (arduino mode only)
                if (effectiveMode == DetectionMode.arduino)
                  PaceTimeline(paceHistory: _paceHistory),

                const Spacer(flex: 3),

                // Finish button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _confirmEnd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: Text(
                      'Finish Workout',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
            // Countdown overlay
            if (_isCountingDown)
              Positioned.fill(
                child: Container(
                  color: AppColors.background.withValues(alpha: 0.92),
                  child: Center(
                    child: Text(
                      '$_countdownValue',
                      style: GoogleFonts.inter(
                        fontSize: 120,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            // Rest warning banner
            if (_showRestWarning)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_rounded,
                          color: AppColors.background,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Long Rest Break',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.background,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Time to get back to work!',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.background.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: AppColors.background,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _showRestWarning = false;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
