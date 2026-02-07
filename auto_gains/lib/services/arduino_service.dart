import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/workout_session.dart';

enum ArduinoConnectionState { disconnected, connecting, connected, error }

class ArduinoService {
  final String wsUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _repController = StreamController<RepData>.broadcast();
  final _connectionStateController =
      StreamController<ArduinoConnectionState>.broadcast();

  Stream<RepData> get repStream => _repController.stream;
  Stream<ArduinoConnectionState> get connectionState =>
      _connectionStateController.stream;

  ArduinoConnectionState _currentState = ArduinoConnectionState.disconnected;
  ArduinoConnectionState get currentState => _currentState;

  DateTime _lastRepTime = DateTime.now();

  ArduinoService({this.wsUrl = 'ws://172.25.18.162:8765'});

  void connect() {
    _updateState(ArduinoConnectionState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _updateState(ArduinoConnectionState.error);
    }
  }

  void _onMessage(dynamic rawMessage) {
    try {
      final data = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'connected':
          _updateState(ArduinoConnectionState.connected);
          _lastRepTime = DateTime.now();
          break;

        case 'rep':
          final amplitude = (data['amplitude'] as num).toDouble();
          final now = DateTime.now();
          final elapsed = now.difference(_lastRepTime);
          _lastRepTime = now;

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
      }
    } catch (_) {
      // Malformed message, ignore
    }
  }

  void _onError(Object error) {
    _updateState(ArduinoConnectionState.error);
  }

  void _onDone() {
    _updateState(ArduinoConnectionState.disconnected);
  }

  void _updateState(ArduinoConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _updateState(ArduinoConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _repController.close();
    _connectionStateController.close();
  }
}
