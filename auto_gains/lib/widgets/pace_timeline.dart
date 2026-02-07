import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PaceTimeline extends StatelessWidget {
  /// Speed deviation values recorded during the current set.
  /// Each value in range [-1.0, 1.0].
  final List<double> paceHistory;

  const PaceTimeline({super.key, required this.paceHistory});

  static Color _colorForDeviation(double deviation) {
    final abs = deviation.abs();
    if (abs < 0.12) return AppColors.primary;
    if (abs < 0.35) return AppColors.accent;
    return AppColors.error;
  }

  double get goodPacePercent {
    if (paceHistory.isEmpty) return 0.0;
    final good = paceHistory.where((d) => d.abs() < 0.12).length;
    return good / paceHistory.length;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pace',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              Text(
                paceHistory.isEmpty
                    ? 'Good Pace: --'
                    : 'Good Pace: ${(goodPacePercent * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: paceHistory.isEmpty
                      ? AppColors.textTertiary
                      : goodPacePercent > 0.6
                          ? AppColors.primary
                          : goodPacePercent > 0.3
                              ? AppColors.accent
                              : AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: paceHistory.isEmpty
                  ? Container(color: AppColors.surfaceLight)
                  : CustomPaint(
                      painter: _PaceBarPainter(paceHistory: paceHistory),
                      size: Size.infinite,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceBarPainter extends CustomPainter {
  final List<double> paceHistory;

  _PaceBarPainter({required this.paceHistory});

  @override
  void paint(Canvas canvas, Size size) {
    if (paceHistory.isEmpty) return;

    final segmentWidth = size.width / paceHistory.length;

    for (int i = 0; i < paceHistory.length; i++) {
      final color = PaceTimeline._colorForDeviation(paceHistory[i]);
      final rect = Rect.fromLTWH(
        i * segmentWidth,
        0,
        segmentWidth + 0.5,
        size.height,
      );
      canvas.drawRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_PaceBarPainter old) =>
      old.paceHistory.length != paceHistory.length;
}
