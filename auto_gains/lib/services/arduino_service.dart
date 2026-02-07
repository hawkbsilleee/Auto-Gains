import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/backend_config.dart';
import '../models/workout_session.dart';

enum ArduinoConnectionState { disconnected, connecting, connected, error }

/// Result of automatic exercise detection: exercise label and reps already counted.
class AutoDetectResult {
  final String exercise;
  final int repCount;

  const AutoDetectResult({required this.exercise, required this.repCount});
}

/// Connection timeout; if we don't get "connected" by then, report error.
const Duration _kConnectionTimeout = Duration(seconds: 10);

class ArduinoService {
  final String wsUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _connectionTimer;

  final _repController = StreamController<RepData>.broadcast();
  final _connectionStateController =
      StreamController<ArduinoConnectionState>.broadcast();
  final _exerciseDetectedController = StreamController<AutoDetectResult>.broadcast();

  Stream<RepData> get repStream => _repController.stream;
  Stream<ArduinoConnectionState> get connectionState =>
      _connectionStateController.stream;
  /// Fired once when backend sends exercise_detected (exercise label + rep count so far).
  Stream<AutoDetectResult> get exerciseDetectedStream =>
      _exerciseDetectedController.stream;

  ArduinoConnectionState _currentState = ArduinoConnectionState.disconnected;
  ArduinoConnectionState get currentState => _currentState;

  DateTime _lastRepTime = DateTime.now();

  ArduinoService({String? wsUrl}) : wsUrl = wsUrl ?? kBackendWsUrl;

  void connect() {
    _updateState(ArduinoConnectionState.connecting);
    _connectionTimer?.cancel();
    _connectionTimer = Timer(_kConnectionTimeout, () {
      if (_currentState == ArduinoConnectionState.connecting) {
        _updateState(ArduinoConnectionState.error);
      }
    });
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _connectionTimer?.cancel();
      _connectionTimer = null;
      _updateState(ArduinoConnectionState.error);
    }
  }

  void _onMessage(dynamic rawMessage) {
    try {
      final data = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      // Debug: confirm frontend is receiving data from backend
      if (type == 'status') {
        // Log status less often to avoid spam (every 500 samples)
        final sampleIdx = data['sample_idx'] as int? ?? 0;
        if (sampleIdx % 500 == 0 && sampleIdx > 0) {
          print('[flutter] WS received: type=status sample_idx=$sampleIdx');
        }
      } else {
        print('[flutter] WS received: type=$type');
      }

      switch (type) {
        case 'connected':
          _connectionTimer?.cancel();
          _connectionTimer = null;
          _updateState(ArduinoConnectionState.connected);
          _lastRepTime = DateTime.now();
          break;

        case 'rep':
          final amplitude = (data['amplitude'] as num).toDouble();
          final now = DateTime.now();
          final elapsed = now.difference(_lastRepTime);
          _lastRepTime = now;

          print('[flutter] REP received from backend: amplitude=$amplitude -> forwarding to UI');
          _repController.add(RepData(
            timestamp: now,
            peakAcceleration: amplitude,
            repDuration: elapsed,
            intensity: (amplitude / 80.0).clamp(0.0, 1.0),
          ));
          break;

        case 'status':
          // Heartbeat — connection alive
          break;

        case 'reset_ack':
          _lastRepTime = DateTime.now();
          break;

        case 'exercise_detected':
          final exercise = data['exercise'] as String?;
          final repCount = (data['rep_count'] as num?)?.toInt() ?? 0;
          if (exercise != null && !_exerciseDetectedController.isClosed) {
            _exerciseDetectedController.add(AutoDetectResult(
              exercise: exercise,
              repCount: repCount,
            ));
          }
          break;

        case 'auto_detect_started':
          break;
      }
    } catch (_) {
      // Malformed message, ignore
    }
  }

  void _onError(Object error) {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _updateState(ArduinoConnectionState.error);
  }

  void _onDone() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _updateState(ArduinoConnectionState.disconnected);
  }

  void _updateState(ArduinoConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// Ask backend to run exercise classification on the next ~4 sec of IMU data.
  void startAutoDetect() {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'action': 'start_auto_detect'}));
    } catch (_) {}
  }

  void disconnect() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _updateState(ArduinoConnectionState.disconnected);
  }

  /// Disconnect and connect again (e.g. after backend was started).
  void reconnect() {
    disconnect();
    connect();
  }

  void dispose() {
    disconnect();
    _repController.close();
    _connectionStateController.close();
    _exerciseDetectedController.close();
  }
}
