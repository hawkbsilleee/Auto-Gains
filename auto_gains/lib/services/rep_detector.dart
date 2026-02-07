import 'dart:async';
import 'dart:math';
import '../models/workout_session.dart';
import 'sensor_service.dart';

class RepDetector {
  final bool simulationMode;
  final _repController = StreamController<RepData>.broadcast();
  Stream<RepData> get repStream => _repController.stream;

  Timer? _simTimer;
  final _random = Random();
  int _simRepCount = 0;

  StreamSubscription? _sensorSub;
  double _smoothed = 0;
  double _prev = 0;
  bool _ascending = false;
  DateTime _lastRepTime = DateTime.now();

  static const _cooldownMs = 800;
  static const _threshold = 1.5;
  static const _alpha = 0.3;

  RepDetector({this.simulationMode = true});

  void start([SensorService? sensorService]) {
    _lastRepTime = DateTime.now();
    if (simulationMode) {
      _startSimulation();
    } else if (sensorService != null) {
      _startDetection(sensorService);
    }
  }

  void _startSimulation() {
    _simRepCount = 0;
    _scheduleNextRep();
  }

  void _scheduleNextRep() {
    final delay = 1600 + _random.nextInt(1000);
    _simTimer = Timer(Duration(milliseconds: delay), () {
      if (_repController.isClosed) return;
      _simRepCount++;
      final fatigue = 1.0 - (_simRepCount * 0.015).clamp(0.0, 0.25);
      final intensity = (0.65 + _random.nextDouble() * 0.35) * fatigue;
      _repController.add(RepData(
        timestamp: DateTime.now(),
        peakAcceleration: 4.0 + _random.nextDouble() * 12.0,
        repDuration: Duration(milliseconds: 1200 + _random.nextInt(800)),
        intensity: intensity.clamp(0.0, 1.0),
      ));
      _scheduleNextRep();
    });
  }

  void _startDetection(SensorService sensor) {
    _sensorSub = sensor.stream.listen((data) {
      _prev = _smoothed;
      _smoothed = _smoothed * (1 - _alpha) + data.magnitude * _alpha;

      final wasAscending = _ascending;
      _ascending = _smoothed > _prev;

      if (wasAscending && !_ascending && _prev > _threshold) {
        final now = DateTime.now();
        final elapsed = now.difference(_lastRepTime).inMilliseconds;
        if (elapsed > _cooldownMs) {
          _lastRepTime = now;
          _repController.add(RepData(
            timestamp: now,
            peakAcceleration: _prev,
            repDuration: Duration(milliseconds: elapsed),
            intensity: (_prev / 12.0).clamp(0.0, 1.0),
          ));
        }
      }
    });
  }

  void stop() {
    _simTimer?.cancel();
    _sensorSub?.cancel();
  }

  void dispose() {
    stop();
    _repController.close();
  }
}
