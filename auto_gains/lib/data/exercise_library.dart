import '../models/exercise.dart';

final List<Exercise> exerciseLibrary = [
  // Chest
  const Exercise(
    id: 'bench_press',
    name: 'Bench Press',
    primaryMuscle: MuscleGroup.chest,
    secondaryMuscles: [MuscleGroup.arms, MuscleGroup.shoulders],
    description: 'Flat barbell bench press',
  ),
  const Exercise(
    id: 'push_ups',
    name: 'Push Ups',
    primaryMuscle: MuscleGroup.chest,
    secondaryMuscles: [MuscleGroup.arms, MuscleGroup.core],
    description: 'Bodyweight push ups',
  ),
  const Exercise(
    id: 'dumbbell_fly',
    name: 'Dumbbell Fly',
    primaryMuscle: MuscleGroup.chest,
    description: 'Flat bench dumbbell fly',
  ),

  // Back
  const Exercise(
    id: 'pull_ups',
    name: 'Pull Ups',
    primaryMuscle: MuscleGroup.back,
    secondaryMuscles: [MuscleGroup.arms],
    description: 'Bodyweight pull ups',
  ),
  const Exercise(
    id: 'barbell_row',
    name: 'Barbell Row',
    primaryMuscle: MuscleGroup.back,
    secondaryMuscles: [MuscleGroup.arms],
    description: 'Bent-over barbell row',
  ),
  const Exercise(
    id: 'lat_pulldown',
    name: 'Lat Pulldown',
    primaryMuscle: MuscleGroup.back,
    secondaryMuscles: [MuscleGroup.arms],
    description: 'Cable lat pulldown',
  ),

  // Shoulders
  const Exercise(
    id: 'overhead_press',
    name: 'Overhead Press',
    primaryMuscle: MuscleGroup.shoulders,
    secondaryMuscles: [MuscleGroup.arms],
    description: 'Standing barbell overhead press',
  ),
  const Exercise(
    id: 'lateral_raise',
    name: 'Lateral Raise',
    primaryMuscle: MuscleGroup.shoulders,
    description: 'Dumbbell lateral raise',
  ),

  // Arms
  const Exercise(
    id: 'bicep_curl',
    name: 'Bicep Curl',
    primaryMuscle: MuscleGroup.arms,
    description: 'Dumbbell bicep curl',
  ),
  const Exercise(
    id: 'tricep_dip',
    name: 'Tricep Dip',
    primaryMuscle: MuscleGroup.arms,
    secondaryMuscles: [MuscleGroup.chest],
    description: 'Bodyweight tricep dip',
  ),
  const Exercise(
    id: 'hammer_curl',
    name: 'Hammer Curl',
    primaryMuscle: MuscleGroup.arms,
    description: 'Dumbbell hammer curl',
  ),

  // Legs
  const Exercise(
    id: 'squat',
    name: 'Squat',
    primaryMuscle: MuscleGroup.legs,
    secondaryMuscles: [MuscleGroup.core],
    description: 'Barbell back squat',
  ),
  const Exercise(
    id: 'deadlift',
    name: 'Deadlift',
    primaryMuscle: MuscleGroup.legs,
    secondaryMuscles: [MuscleGroup.back, MuscleGroup.core],
    description: 'Conventional deadlift',
  ),
  const Exercise(
    id: 'lunges',
    name: 'Lunges',
    primaryMuscle: MuscleGroup.legs,
    description: 'Walking lunges',
  ),
  const Exercise(
    id: 'leg_press',
    name: 'Leg Press',
    primaryMuscle: MuscleGroup.legs,
    description: 'Machine leg press',
  ),

  // Core
  const Exercise(
    id: 'plank',
    name: 'Plank',
    primaryMuscle: MuscleGroup.core,
    description: 'Isometric plank hold',
  ),
  const Exercise(
    id: 'crunches',
    name: 'Crunches',
    primaryMuscle: MuscleGroup.core,
    description: 'Abdominal crunches',
  ),

  // Full Body
  const Exercise(
    id: 'burpees',
    name: 'Burpees',
    primaryMuscle: MuscleGroup.fullBody,
    description: 'Full body burpees',
  ),
  const Exercise(
    id: 'clean_press',
    name: 'Clean & Press',
    primaryMuscle: MuscleGroup.fullBody,
    secondaryMuscles: [MuscleGroup.shoulders, MuscleGroup.legs],
    description: 'Barbell clean and press',
  ),
];

Map<MuscleGroup, List<Exercise>> get exercisesByMuscle {
  final map = <MuscleGroup, List<Exercise>>{};
  for (final exercise in exerciseLibrary) {
    map.putIfAbsent(exercise.primaryMuscle, () => []).add(exercise);
  }
  return map;
}
