// weekly_leaderboard_screen.dart - updated to show all users
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:LifeCompanion/services/auth_service.dart';
import 'package:intl/intl.dart';

class WeeklyLeaderboardScreen extends StatefulWidget {
  const WeeklyLeaderboardScreen({super.key});

  @override
  State<WeeklyLeaderboardScreen> createState() => _WeeklyLeaderboardScreenState();
}

class _WeeklyLeaderboardScreenState extends State<WeeklyLeaderboardScreen> {
  final _auth = AuthService();
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _leaderboardData = [];
  String _weekRange = '';

  // Get the week start date (Tuesday 1:00 PM)
  DateTime _getWeekStart() {
    final now = DateTime.now();
    
    // Start with today at 1:00 PM
    DateTime weekStart = DateTime(now.year, now.month, now.day, 13, 0);
    
    // Find the most recent Tuesday
    // DateTime.weekday: Monday = 1, Tuesday = 2, ..., Sunday = 7
    int daysToSubtract = weekStart.weekday - 2;
    
    // If today is before Tuesday 1:00 PM, go back to previous Tuesday
    if (daysToSubtract < 0 || (weekStart.weekday == 2 && now.hour < 13)) {
      daysToSubtract += 7;
    }
    
    weekStart = weekStart.subtract(Duration(days: daysToSubtract));
    
    // If we've gone past the current time, go back another week
    if (weekStart.isAfter(now)) {
      weekStart = weekStart.subtract(const Duration(days: 7));
    }
    
    return weekStart;
  }

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);

    try {
      final weekStart = _getWeekStart();
      final weekEnd = weekStart.add(const Duration(days: 7));
      
      final dateFormat = DateFormat('MMM d, yyyy');
      _weekRange = '${dateFormat.format(weekStart)} - ${dateFormat.format(weekEnd)}';

      // Get all users
      final usersSnapshot = await _firestore.collection('users').get();
      
      List<Map<String, dynamic>> leaderboardEntries = [];

      for (var userDoc in usersSnapshot.docs) {
        final uid = userDoc.id;
        final username = userDoc.data()['username'] as String? ?? 'Unknown';
        final name = userDoc.data()['name'] as String? ?? '';
        
        // Calculate points for this user
        final points = await _calculateUserPoints(uid, weekStart, weekEnd);
        
        // Always add the user, even if total points is 0
        leaderboardEntries.add({
          'username': username,
          'name': name,
          'uid': uid,
          'gymPoints': points['gym'] ?? 0,
          'prayerPoints': points['prayer'] ?? 0,
          'weightPoints': points['weight'] ?? 0,
          'total': points['total'] ?? 0,
        });
      }

      // Sort by total points descending
      leaderboardEntries.sort((a, b) => b['total'].compareTo(a['total']));

      setState(() {
        _leaderboardData = leaderboardEntries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading leaderboard: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, int>> _calculateUserPoints(String uid, DateTime weekStart, DateTime weekEnd) async {
    Map<String, int> points = {
      'gym': 0,
      'prayer': 0,
      'weight': 0,
      'total': 0,
    };

    try {
      // 1. Gym Points: 2 points for each increased exercise weight
      // Get all exercise entries for this week
      final exercisesSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('exercises')
          .where('date', isGreaterThanOrEqualTo: weekStart)
          .where('date', isLessThan: weekEnd)
          .orderBy('date')
          .get();

      // Track previous weight per exercise to calculate increases
      Map<String, double> previousWeights = {};
      Map<String, String> exerciseKeys = {};
      
      for (var doc in exercisesSnapshot.docs) {
        final data = doc.data();
        final exerciseName = data['exerciseName'] as String? ?? '';
        final weight = (data['weight'] as num?)?.toDouble() ?? 0;
        final muscleGroup = data['muscleGroup'] as String? ?? '';

        // Use a more specific key
        String key = '$muscleGroup-$exerciseName';
        exerciseKeys[key] = exerciseName;
        
        // Check if this exercise was done before with lower weight
        if (previousWeights.containsKey(key)) {
          if (weight > previousWeights[key]!) {
            points['gym'] = (points['gym'] ?? 0) + 2;
          }
        }
        // Only update if this is the latest weight for this exercise
        if (!previousWeights.containsKey(key) || weight > previousWeights[key]!) {
          previousWeights[key] = weight;
        }
      }

      // 2. Prayer Points
      // Get all prayer entries for this week
      final prayersSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('prayers')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(weekStart))
          .where(FieldPath.documentId, isLessThan: DateFormat('yyyy-MM-dd').format(weekEnd))
          .get();

      List<String> prayerNames = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
      
      // Get all dates in the week range
      List<String> weekDates = [];
      DateTime current = weekStart;
      while (current.isBefore(weekEnd)) {
        weekDates.add(DateFormat('yyyy-MM-dd').format(current));
        current = current.add(const Duration(days: 1));
      }
      
      // Process each day's prayers
      for (String date in weekDates) {
        // Check if this date exists in the prayers collection
        final docSnapshot = await _firestore
            .collection('users')
            .doc(uid)
            .collection('prayers')
            .doc(date)
            .get();
        
        final data = docSnapshot.data();
        
        for (String prayerName in prayerNames) {
          if (data != null && data.containsKey(prayerName)) {
            final prayerData = data[prayerName] as Map<String, dynamic>?;
            if (prayerData != null) {
              final onTime = prayerData['onTime'] == true;
              final delayed = prayerData['delayed'] == true;
              final inMosque = prayerData['inMosque'] == true;

              // Calculate points for this prayer
              if (inMosque) {
                points['prayer'] = (points['prayer'] ?? 0) + 5;
              } else if (onTime) {
                points['prayer'] = (points['prayer'] ?? 0) + 3;
              } else if (delayed) {
                points['prayer'] = (points['prayer'] ?? 0) + 1;
              } else {
                // Prayer logged but all false = missed
                points['prayer'] = (points['prayer'] ?? 0) - 1;
              }
            } else {
              // Prayer logged but empty = missed
              points['prayer'] = (points['prayer'] ?? 0) - 0;
            }
          } else {
            // Prayer not logged = missed
            points['prayer'] = (points['prayer'] ?? 0) - 0;
          }
        }
      }

      // 3. Weight Points: 1 point for each 100gm lost
      // Get weight entries for this week
      final weightSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('weight')
          .where('date', isGreaterThanOrEqualTo: weekStart)
          .where('date', isLessThan: weekEnd)
          .orderBy('date')
          .get();

      if (weightSnapshot.docs.isNotEmpty) {
        // Get the first and last weight of the week
        final firstWeight = weightSnapshot.docs.first.data()['weight'] as num?;
        final lastWeight = weightSnapshot.docs.last.data()['weight'] as num?;
        
        if (firstWeight != null && lastWeight != null) {
          final weightLost = firstWeight.toDouble() - lastWeight.toDouble();
          if (weightLost > 0) {
            // 1 point per 100gm (0.1 kg)
            final pointsEarned = (weightLost * 10).floor();
            points['weight'] = (points['weight'] ?? 0) + pointsEarned;
          }
        }
      }

      points['total'] = (points['gym'] ?? 0) + (points['prayer'] ?? 0) + (points['weight'] ?? 0);
      return points;
    } catch (e) {
      // Return the points we have so far
      points['total'] = (points['gym'] ?? 0) + (points['prayer'] ?? 0) + (points['weight'] ?? 0);
      return points;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Leaderboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Week: $_weekRange',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_leaderboardData.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('No users found'),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: DataTable(
                            columnSpacing: 8,
                            headingRowColor: MaterialStateProperty.resolveWith(
                              (states) => Theme.of(context).colorScheme.primaryContainer,
                            ),
                            columns: const [
                              DataColumn(
                                label: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(
                                label: Text('Username', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(
                                label: Text('Gym', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(
                                label: Text('Prayer', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(
                                label: Text('Weight', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(
                                label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                            rows: _leaderboardData.asMap().entries.map((entry) {
                              final index = entry.key;
                              final user = entry.value;
                              final isCurrentUser = user['uid'] == FirebaseAuth.instance.currentUser?.uid;
                              final totalPoints = user['total'] ?? 0;
                              
                              return DataRow(
                                color: isCurrentUser
                                    ? MaterialStateProperty.resolveWith(
                                        (states) => Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                                      )
                                    : null,
                                cells: [
                                  DataCell(
                                    Row(
                                      children: [
                                        if (index < 3 && totalPoints > 0)
                                          Icon(
                                            index == 0 ? Icons.emoji_events : 
                                            index == 1 ? Icons.emoji_events : 
                                            Icons.emoji_events,
                                            color: index == 0 ? Colors.amber : 
                                                   index == 1 ? Colors.grey : 
                                                   Colors.brown,
                                            size: 20,
                                          ),
                                        if (index < 3 && totalPoints > 0)
                                          const SizedBox(width: 4),
                                        Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontWeight: totalPoints > 0 ? FontWeight.bold : FontWeight.normal,
                                            color: totalPoints > 0 ? null : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        Text(
                                          user['username'] ?? 'Unknown',
                                          style: TextStyle(
                                            fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                            color: totalPoints > 0 ? null : Colors.grey,
                                          ),
                                        ),
                                        if (isCurrentUser)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'You',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onPrimary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${user['gymPoints'] ?? 0}',
                                      style: TextStyle(
                                        color: totalPoints > 0 ? null : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${user['prayerPoints'] ?? 0}',
                                      style: TextStyle(
                                        color: totalPoints > 0 ? null : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${user['weightPoints'] ?? 0}',
                                      style: TextStyle(
                                        color: totalPoints > 0 ? null : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '$totalPoints',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: totalPoints > 0 ? null : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Points legend
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How points are earned:',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          const Text('🏋️ Gym: +2 for each increased exercise weight'),
                          const Text('🕌 Prayer in Mosque: +5'),
                          const Text('⏰ Prayer on time: +3'),
                          const Text('⏳ Prayer delayed: +1'),
                          const Text('❌ Prayer missed: -1'),
                          const Text('⚖️ Weight: +1 per 100g lost'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}