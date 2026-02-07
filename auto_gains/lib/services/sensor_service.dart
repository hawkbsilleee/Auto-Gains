import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class SensorData {
  final double x, y, z;
  final double magnitude;
  final DateTime timestamp;

  SensorData({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  }) : magnitude = sqrt(x * x + y * y + z * z);
}

class SensorService {
  StreamSubscription? _accelSub;
  final _controller = StreamController<SensorData>.broadcast();
  Stream<SensorData> get stream => _controller.stream;
  bool _active = false;

  void start() {
    if (_active) return;
    _active = true;
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((event) {
      _controller.add(SensorData(
        x: event.x,
        y: event.y,
        z: event.z,
        timestamp: DateTime.now(),
      ));
    });
  }

  void stop() {
    _active = false;
    _accelSub?.cancel();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
