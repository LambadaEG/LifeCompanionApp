import 'package:flutter/material.dart';
import 'muscle_group_screen.dart';

class _MuscleGroup {
  final String label;
  final IconData icon;
  const _MuscleGroup(this.label, this.icon);
}

class GymMenuScreen extends StatelessWidget {
  const GymMenuScreen({super.key});

  static const _groups = [
    _MuscleGroup('Chest', Icons.accessibility_new),
    _MuscleGroup("Bi's & Tri's", Icons.sports_gymnastics),
    _MuscleGroup('Back', Icons.airline_seat_flat_outlined),
    _MuscleGroup('Leg', Icons.directions_walk),
    _MuscleGroup('Shoulder', Icons.sports_martial_arts),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gym')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final g = _groups[index];
            return Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(g.icon),
                title: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MuscleGroupScreen(muscleGroup: g.label),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
