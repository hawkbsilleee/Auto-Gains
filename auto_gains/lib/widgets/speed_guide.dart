import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';

class SpeedGuideWidget extends StatefulWidget {
  /// Speed deviation from optimal: -1.0 (too slow) to 1.0 (too fast).
  /// Ignored when [simulate] is true.
  final double speedDeviation;

  /// When true, generates fake oscillating speed data internally.
  final bool simulate;

  const SpeedGuideWidget({
    super.key,
    this.speedDeviation = 0.0,
    this.simulate = true,
  });

  @override
  State<SpeedGuideWidget> createState() => _SpeedGuideWidgetState();
}

class _SpeedGuideWidgetState extends State<SpeedGuideWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  double _position = 0.0; // -1.0 (slow side) to 1.0 (fast side)
  double _velocity = 0.0;
  Duration _lastElapsed = Duration.zero;

  // Physics tuning
  static const double _kTrack = 14.0; // restoring force (bowl steepness)
  static const double _kPush = 8.0; // how strongly speed deviation pushes
  static const double _kDamping = 3.5; // friction

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  double _getSpeedDeviation(Duration elapsed) {
    if (widget.simulate) {
      final t = elapsed.inMilliseconds / 1000.0;
      // Layered sine waves for natural-feeling oscillation
      final trend = 0.35 * math.sin(t * 0.5);
      final repVar = 0.25 * math.sin(t * 1.8 + 0.7);
      final jitter = 0.1 * math.sin(t * 4.3 + 2.1);
      return (trend + repVar + jitter).clamp(-1.0, 1.0);
    }
    return widget.speedDeviation;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    final speedDev = _getSpeedDeviation(elapsed);

    // Forces: bowl restoring + external push + damping
    final restore = -_kTrack * _position;
    final push = speedDev * _kPush;
    final damping = -_kDamping * _velocity;
    final accel = restore + push + damping;

    _velocity += accel * dt;
    _position = (_position + _velocity * dt).clamp(-1.0, 1.0);

    // Soft bounce off edges
    if (_position.abs() > 0.98) {
      _velocity *= -0.3;
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _statusText() {
    final abs = _position.abs();
    if (abs < 0.12) return 'Perfect';
    if (abs < 0.35) return 'Good';
    if (_position < 0) return 'Too slow';
    return 'Too fast';
  }

  Color _statusColor() {
    final abs = _position.abs();
    if (abs < 0.12) return AppColors.primary;
    if (abs < 0.35) return AppColors.accent;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tempo',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              Text(
                _statusText(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _statusColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 60,
            child: CustomPaint(
              painter: _TrackPainter(ballPosition: _position),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SLOW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                'FAST',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter: bowl track + ball
// ---------------------------------------------------------------------------

class _TrackPainter extends CustomPainter {
  final double ballPosition; // -1 to 1

  _TrackPainter({required this.ballPosition});

  /// Parabolic bowl in screen coords.
  /// Center (p=0) is the lowest point (largest Y).
  /// Edges (p=±1) curve upward (smaller Y).
  double _trackY(double p, double baseY, double depth) {
    return baseY - depth * p * p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final trackPadding = 12.0;
    final trackLeft = trackPadding;
    final trackRight = w - trackPadding;
    final trackWidth = trackRight - trackLeft;
    final centerX = w / 2;

    final bowlBaseY = h * 0.82; // bottom of bowl
    final bowlDepth = h * 0.52; // how far edges rise
    final ballRadius = 11.0;

    // -- Track fill (subtle gradient under the curve) --
    final fillPath = Path();
    const steps = 120;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = t * 2 - 1;
      final x = trackLeft + t * trackWidth;
      final y = _trackY(p, bowlBaseY, bowlDepth);
      if (i == 0) {
        fillPath.moveTo(x, y);
      } else {
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo(trackRight, h)
      ..lineTo(trackLeft, h)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.surfaceLight.withValues(alpha: 0.25),
          AppColors.surface.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // -- Track stroke --
    final strokePath = Path();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = t * 2 - 1;
      final x = trackLeft + t * trackWidth;
      final y = _trackY(p, bowlBaseY, bowlDepth);
      if (i == 0) {
        strokePath.moveTo(x, y);
      } else {
        strokePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // -- Sweet-spot glow at the bowl center --
    final glowCenter = Offset(centerX, bowlBaseY + 1);
    canvas.drawCircle(
      glowCenter,
      trackWidth * 0.08,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.30),
            AppColors.primary.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: glowCenter, radius: trackWidth * 0.08),
        ),
    );

    // -- Divot notch (small V at the bowl bottom) --
    final divotPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    const dv = 5.0;
    canvas.drawLine(
      Offset(centerX - dv, bowlBaseY - dv * 0.6),
      Offset(centerX, bowlBaseY + dv * 0.35),
      divotPaint,
    );
    canvas.drawLine(
      Offset(centerX, bowlBaseY + dv * 0.35),
      Offset(centerX + dv, bowlBaseY - dv * 0.6),
      divotPaint,
    );

    // -- Ball --
    final bp = ballPosition.clamp(-1.0, 1.0);
    final ballT = (bp + 1) / 2; // 0..1
    final ballX = trackLeft + ballT * trackWidth;
    final ballY = _trackY(bp, bowlBaseY, bowlDepth) - ballRadius - 1;

    // Color: green → amber → red as ball leaves center
    final abs = bp.abs();
    Color ballColor;
    if (abs < 0.12) {
      ballColor = AppColors.primary;
    } else if (abs < 0.45) {
      final t = (abs - 0.12) / 0.33;
      ballColor = Color.lerp(AppColors.primary, AppColors.accent, t)!;
    } else {
      final t = ((abs - 0.45) / 0.55).clamp(0.0, 1.0);
      ballColor = Color.lerp(AppColors.accent, AppColors.error, t)!;
    }

    // Shadow
    canvas.drawCircle(
      Offset(ballX, ballY + 3),
      ballRadius + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Body (radial gradient for 3-D look)
    canvas.drawCircle(
      Offset(ballX, ballY),
      ballRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [
            Color.lerp(ballColor, Colors.white, 0.35)!,
            ballColor,
            Color.lerp(ballColor, Colors.black, 0.4)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(
          Rect.fromCircle(center: Offset(ballX, ballY), radius: ballRadius),
        ),
    );

    // Specular highlight
    canvas.drawCircle(
      Offset(ballX - ballRadius * 0.3, ballY - ballRadius * 0.3),
      ballRadius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.ballPosition != ballPosition;
}
