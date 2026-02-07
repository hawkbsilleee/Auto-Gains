import '../models/workout_session.dart';

class WorkoutStore {
  static final WorkoutStore instance = WorkoutStore._();
  WorkoutStore._();

  final List<WorkoutSession> _sessions = [];

  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  void add(WorkoutSession session) {
    _sessions.insert(0, session);
  }

  int get totalWorkouts => _sessions.length;
  int get totalRepsAllTime => _sessions.fold(0, (sum, s) => sum + s.totalReps);
}
