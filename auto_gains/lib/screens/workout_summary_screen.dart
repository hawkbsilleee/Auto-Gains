import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../models/workout_session.dart';
import '../widgets/metric_card.dart';

class WorkoutSummaryScreen extends StatelessWidget {
  final WorkoutSession session;

  const WorkoutSummaryScreen({super.key, required this.session});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}h ${m}m';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final allPace = session.allPaceDeviations;
    final hasPaceData = allPace.isNotEmpty;
    final exerciseName =
        session.sets.isNotEmpty ? session.sets.first.exercise.name : 'Workout';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 24),
              _buildHeader(exerciseName),
              const SizedBox(height: 28),
              _buildTopMetrics(hasPaceData),
              const SizedBox(height: 28),
              if (session.sets.isNotEmpty) ...[
                _sectionTitle('Sets'),
                const SizedBox(height: 12),
                ...session.sets.map(_buildSetRow),
                const SizedBox(height: 24),
              ],
              if (hasPaceData) ...[
                _sectionTitle('Pace Over Time'),
                const SizedBox(height: 12),
                _buildPaceChart(allPace),
                const SizedBox(height: 28),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String exerciseName) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: AppColors.primary, size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          'Workout Complete',
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          exerciseName,
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _fmt(session.duration),
          style: const TextStyle(fontSize: 15, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildTopMetrics(bool hasPaceData) {
    final hasVolume = session.totalVolume > 0;

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: 'Total Sets',
            value: '${session.totalSets}',
            icon: Icons.layers,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricCard(
            label: 'Total Reps',
            value: '${session.totalReps}',
            icon: Icons.repeat,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricCard(
            label: hasVolume ? 'Volume' : 'Good Pace',
            value: hasVolume
                ? '${session.totalVolume.toStringAsFixed(0)} lbs'
                : hasPaceData
                    ? '${(session.overallGoodPacePercent * 100).toInt()}%'
                    : '--',
            icon: hasVolume ? Icons.fitness_center : Icons.speed,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildSetRow(WorkoutSet set) {
    final hasPace = set.paceDeviations.isNotEmpty;
    final pacePercent = set.goodPacePercent;
    final paceColor = !hasPace
        ? AppColors.textTertiary
        : pacePercent > 0.6
            ? AppColors.primary
            : pacePercent > 0.3
                ? AppColors.accent
                : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Set number badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${set.setNumber}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Reps and weight
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${set.reps.length} reps',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (set.weight != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${set.weight!.toStringAsFixed(0)} lbs',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Good pace %
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasPace ? '${(pacePercent * 100).toInt()}%' : '--',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: paceColor,
                ),
              ),
              const Text(
                'good pace',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaceChart(List<double> paceData) {
    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: LineChart(
        LineChartData(
          minY: -1,
          maxY: 1,
          clipData: const FlClipData.all(),
          lineBarsData: [
            // Green zone fill (good pace band)
            LineChartBarData(
              spots: [
                const FlSpot(0, 0.12),
                FlSpot(paceData.length.toDouble() - 1, 0.12),
              ],
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.07),
                cutOffY: -0.12,
                applyCutOffY: true,
              ),
            ),
            // Actual pace line
            LineChartBarData(
              spots: [
                for (int i = 0; i < paceData.length; i++)
                  FlSpot(i.toDouble(), paceData[i].clamp(-1.0, 1.0)),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              color: AppColors.accent,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withValues(alpha: 0.08),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 0.5,
                getTitlesWidget: (value, _) {
                  if (value == 0) {
                    return const Text('0',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textTertiary));
                  }
                  if (value == 0.5 || value == -0.5) {
                    return Text(
                      value > 0 ? 'Fast' : 'Slow',
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textTertiary),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.border.withValues(alpha: 0.4),
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              // Zero line
              HorizontalLine(
                y: 0,
                color: AppColors.textTertiary.withValues(alpha: 0.3),
                strokeWidth: 1,
              ),
              // Good zone boundaries
              HorizontalLine(
                y: 0.12,
                color: AppColors.primary.withValues(alpha: 0.3),
                strokeWidth: 0.5,
                dashArray: [4, 4],
              ),
              HorizontalLine(
                y: -0.12,
                color: AppColors.primary.withValues(alpha: 0.3),
                strokeWidth: 0.5,
                dashArray: [4, 4],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
