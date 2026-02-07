import 'package:flutter/material.dart';

enum MuscleGroup {
  chest('Chest', Icons.fitness_center, Color(0xFFEF4444)),
  back('Back', Icons.accessibility_new, Color(0xFF3B82F6)),
  shoulders('Shoulders', Icons.accessibility, Color(0xFFF59E0B)),
  arms('Arms', Icons.front_hand, Color(0xFF8B5CF6)),
  legs('Legs', Icons.directions_walk, Color(0xFF10B981)),
  core('Core', Icons.circle_outlined, Color(0xFFEC4899)),
  fullBody('Full Body', Icons.person, Color(0xFF6366F1));

  const MuscleGroup(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

class Exercise {
  final String id;
  final String name;
  final MuscleGroup primaryMuscle;
  final List<MuscleGroup> secondaryMuscles;
  final String description;

  const Exercise({
    required this.id,
    required this.name,
    required this.primaryMuscle,
    this.secondaryMuscles = const [],
    required this.description,
  });

  @override
  bool operator ==(Object other) => other is Exercise && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
