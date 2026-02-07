import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/exercise.dart';
import '../data/exercise_library.dart';
import '../config/backend_config.dart';
import '../services/arduino_service.dart';
import '../services/rep_detector.dart';
import 'active_workout_screen.dart';

/// Screen that connects to the backend, runs automatic exercise detection
/// (shoulders vs. biceps), then navigates to [ActiveWorkoutScreen] with the
/// detected exercise for rep tracking.
class WorkoutDetectionScreen extends StatefulWidget {
  const WorkoutDetectionScreen({super.key});

  @override
  State<WorkoutDetectionScreen> createState() => _WorkoutDetectionScreenState();
}

class _WorkoutDetectionScreenState extends State<WorkoutDetectionScreen> {
  final ArduinoService _arduino = ArduinoService(wsUrl: kBackendWsUrl);
  StreamSubscription<ArduinoConnectionState>? _stateSub;
  StreamSubscription<AutoDetectResult>? _detectedSub;
  bool _passedArduinoToWorkout = false;

  ArduinoConnectionState _connectionState = ArduinoConnectionState.disconnected;
  bool _detectionStarted = false;
  AutoDetectResult? _detectedResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateSub = _arduino.connectionState.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });
    _detectedSub = _arduino.exerciseDetectedStream.listen((result) {
      if (mounted) {
        setState(() {
          _detectedResult = result;
          _error = null;
        });
        _navigateToWorkout();
      }
    });
    _arduino.connect();
  }

  void _navigateToWorkout() {
    final result = _detectedResult;
    if (result == null || !mounted) return;
    final exercise = exerciseFromClassifierLabel(result.exercise);
    if (exercise == null) return;
    _passedArduinoToWorkout = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(
          exercises: [exercise],
          detectionMode: DetectionMode.arduino,
          arduinoService: _arduino,
          initialRepCount: result.repCount,
        ),
      ),
    );
  }

  void _startDetection() {
    if (_connectionState != ArduinoConnectionState.connected) {
      setState(() => _error = 'Connect to the backend first (IMU/Arduino).');
      return;
    }
    setState(() {
      _detectionStarted = true;
      _error = null;
      _detectedResult = null;
    });
    _arduino.startAutoDetect();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _detectedSub?.cancel();
    if (!_passedArduinoToWorkout) _arduino.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connectionState == ArduinoConnectionState.connected;
    final connecting = _connectionState == ArduinoConnectionState.connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automatic workout detection'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Do a few reps (shoulders or biceps). We\'ll detect the exercise and then track your reps.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              _buildConnectionChip(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (!_detectionStarted) ...[
                if (_connectionState == ArduinoConnectionState.error)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _arduino.reconnect();
                      },
                      child: const Text('Retry connection'),
                    ),
                  ),
                ElevatedButton(
                  onPressed: connecting ? null : _startDetection,
                  child: Text(
                    connected
                        ? 'Start detection'
                        : connecting
                            ? 'Connecting…'
                            : 'Start detection (connect first)',
                  ),
                ),
              ]
              else
                Column(
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Do a few reps now…',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionChip() {
    final color = switch (_connectionState) {
      ArduinoConnectionState.connected => AppColors.primary,
      ArduinoConnectionState.connecting => AppColors.accent,
      ArduinoConnectionState.error => AppColors.error,
      ArduinoConnectionState.disconnected => AppColors.textTertiary,
    };
    final label = switch (_connectionState) {
      ArduinoConnectionState.connected => 'IMU connected',
      ArduinoConnectionState.connecting => 'Connecting…',
      ArduinoConnectionState.error => 'Connection failed',
      ArduinoConnectionState.disconnected => 'Not connected',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
