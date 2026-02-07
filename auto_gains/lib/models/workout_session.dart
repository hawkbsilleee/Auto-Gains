import 'exercise.dart';

class RepData {
  final DateTime timestamp;
  final double peakAcceleration;
  final Duration repDuration;
  final double intensity;

  RepData({
    required this.timestamp,
    required this.peakAcceleration,
    required this.repDuration,
    required this.intensity,
  });
}

class WorkoutSet {
  Exercise exercise;
  final List<RepData> reps = [];
  final List<double> paceDeviations = [];
  final DateTime startTime;
  DateTime? endTime;
  final int setNumber;

  WorkoutSet({
    required this.exercise,
    required this.startTime,
    this.setNumber = 1,
  });

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  double get averageIntensity {
    if (reps.isEmpty) return 0;
    return reps.map((r) => r.intensity).reduce((a, b) => a + b) / reps.length;
  }

  double get peakIntensity {
    if (reps.isEmpty) return 0;
    return reps.map((r) => r.intensity).reduce((a, b) => a > b ? a : b);
  }

  double get goodPacePercent {
    if (paceDeviations.isEmpty) return 0.0;
    final good = paceDeviations.where((d) => d.abs() < 0.12).length;
    return good / paceDeviations.length;
  }

  double get fatigueIndex {
    if (reps.length < 6) return 0;
    final third = reps.length ~/ 3;
    final early = reps.sublist(0, third);
    final late_ = reps.sublist(reps.length - third);
    final earlyAvg =
        early.map((r) => r.intensity).reduce((a, b) => a + b) / early.length;
    final lateAvg =
        late_.map((r) => r.intensity).reduce((a, b) => a + b) / late_.length;
    return ((earlyAvg - lateAvg) / earlyAvg).clamp(0.0, 1.0);
  }
}

class WorkoutSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  final List<WorkoutSet> sets = [];

  WorkoutSession({required this.id, required this.startTime});

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
  int get totalReps => sets.fold(0, (sum, s) => sum + s.reps.length);
  int get totalSets => sets.length;

  double get averageIntensity {
    final allReps = sets.expand((s) => s.reps).toList();
    if (allReps.isEmpty) return 0;
    return allReps.map((r) => r.intensity).reduce((a, b) => a + b) /
        allReps.length;
  }

  double get overallFatigue {
    final fatigues =
        sets.where((s) => s.fatigueIndex > 0).map((s) => s.fatigueIndex);
    if (fatigues.isEmpty) return 0;
    return fatigues.reduce((a, b) => a + b) / fatigues.length;
  }

  Set<Exercise> get exercises => sets.map((s) => s.exercise).toSet();

  Map<String, int> get repsPerExercise {
    final map = <String, int>{};
    for (final set in sets) {
      map[set.exercise.name] = (map[set.exercise.name] ?? 0) + set.reps.length;
    }
    return map;
  }

  /// All pace deviation samples across every set.
  List<double> get allPaceDeviations =>
      sets.expand((s) => s.paceDeviations).toList();

  /// Fraction of all pace samples that were "good" (abs deviation < 0.12).
  double get overallGoodPacePercent {
    final all = allPaceDeviations;
    if (all.isEmpty) return 0.0;
    final good = all.where((d) => d.abs() < 0.12).length;
    return good / all.length;
  }
}
