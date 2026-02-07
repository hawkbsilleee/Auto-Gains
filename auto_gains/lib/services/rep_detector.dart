import 'dart:async';
import 'dart:math';
import '../config/backend_config.dart';
import '../models/workout_session.dart';
import 'sensor_service.dart';
import 'arduino_service.dart';

enum DetectionMode { simulation, sensor, arduino }

class RepDetector {
  final DetectionMode mode;
  final _repController = StreamController<RepData>.broadcast();
  Stream<RepData> get repStream => _repController.stream;

  // Simulation fields
  Timer? _simTimer;
  final _random = Random();
  int _simRepCount = 0;

  // Sensor fields
  StreamSubscription? _sensorSub;
  double _smoothed = 0;
  double _prev = 0;
  bool _ascending = false;
  DateTime _lastRepTime = DateTime.now();

  static const _cooldownMs = 800;
  static const _threshold = 1.5;
  static const _alpha = 0.3;

  // Arduino fields
  ArduinoService? _arduinoService;
  StreamSubscription? _arduinoRepSub;
  final String wsUrl;
  /// When true, we created the service and must dispose it. When false, caller owns it.
  bool _ownsArduinoService = true;

  Stream<ArduinoConnectionState>? get connectionState =>
      _arduinoService?.connectionState;

  RepDetector({
    this.mode = DetectionMode.simulation,
    this.wsUrl = kBackendWsUrl,
    ArduinoService? existingArduinoService,
  }) {
    if (existingArduinoService != null) {
      _arduinoService = existingArduinoService;
      _ownsArduinoService = false;
    }
  }

  void start([SensorService? sensorService]) {
    _lastRepTime = DateTime.now();
    switch (mode) {
      case DetectionMode.simulation:
        _startSimulation();
        break;
      case DetectionMode.sensor:
        if (sensorService != null) _startDetection(sensorService);
        break;
      case DetectionMode.arduino:
        _startArduino();
        break;
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

  void _startArduino() {
    if (_arduinoService == null) {
      _arduinoService = ArduinoService(wsUrl: wsUrl);
      _ownsArduinoService = true;
      _arduinoService!.connect();
    }
    _arduinoRepSub = _arduinoService!.repStream.listen((repData) {
      if (!_repController.isClosed) {
        _repController.add(repData);
      }
    });
  }

  void stop() {
    _simTimer?.cancel();
    _sensorSub?.cancel();
    _arduinoRepSub?.cancel();
    if (_ownsArduinoService) _arduinoService?.disconnect();
  }

  /// Retry connecting to the backend (Arduino mode only).
  void reconnectArduino() {
    _arduinoService?.reconnect();
  }

  void dispose() {
    stop();
    if (_ownsArduinoService) _arduinoService?.dispose();
    _repController.close();
  }
}
