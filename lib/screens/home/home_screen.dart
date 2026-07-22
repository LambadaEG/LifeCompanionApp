import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/square_icon_button.dart';
import '../gym/gym_menu_screen.dart';
import '../prayer/prayer_screen.dart';
import '../weight/weight_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final name = auth.currentUser?.displayName ?? 'there';

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, $name 👋'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              SquareIconButton(
                icon: Icons.fitness_center,
                label: 'GYM',
                color: Colors.deepOrange,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GymMenuScreen()),
                ),
              ),
              SquareIconButton(
                icon: Icons.mosque,
                label: 'Prayer',
                color: Colors.teal,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrayerScreen()),
                ),
              ),
              SquareIconButton(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight',
                color: Colors.indigo,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WeightScreen()),
                ),
              ),
              const SquareIconButton(
                icon: Icons.hourglass_empty,
                label: 'Coming Soon',
                color: Colors.grey,
                disabled: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
