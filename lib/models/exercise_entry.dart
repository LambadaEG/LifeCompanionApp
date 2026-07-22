import 'package:cloud_firestore/cloud_firestore.dart';

class ExerciseEntry {
  final String id;
  final String exerciseName;
  final double weight;
  final int? reps;
  final DateTime date;

  ExerciseEntry({
    required this.id,
    required this.exerciseName,
    required this.weight,
    this.reps,
    required this.date,
  });

  factory ExerciseEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ExerciseEntry(
      id: doc.id,
      exerciseName: data['exerciseName'] as String? ?? '',
      weight: (data['weight'] as num?)?.toDouble() ?? 0,
      reps: (data['reps'] as num?)?.toInt(),
      date: (data['date'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap({required String muscleGroup}) {
    return {
      'muscleGroup': muscleGroup,
      'exerciseName': exerciseName,
      'weight': weight,
      'reps': reps,
      'date': Timestamp.fromDate(date),
    };
  }
}
