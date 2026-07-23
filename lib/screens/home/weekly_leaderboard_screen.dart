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
  
  // Debug variables
  bool _debugMode = false;
  String _debugInfo = '';
  Map<String, dynamic> _debugData = {};

  // Get the week start date (Tuesday 1:00 PM)
  DateTime _getWeekStart() {
    final now = DateTime.now();
    
    // Start with today at 00:01 AM
    DateTime weekStart = DateTime(now.year, now.month, now.day, 0, 0);
    
    // Find the most recent Tuesday
    // DateTime.weekday: Monday = 1, Tuesday = 2, ..., Sunday = 7
    int daysToSubtract = weekStart.weekday - 2;
    
    // If today is before Tuesday 00:01 AM, go back to previous Tuesday
    if (daysToSubtract < 0 || (weekStart.weekday == 2 && now.hour < 0)) {
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
    _debugInfo = '';
    _debugData = {};

    try {
      final weekStart = _getWeekStart();
      final weekEnd = weekStart.add(const Duration(days: 7));
      
      final dateFormat = DateFormat('MMM d, yyyy');
      _weekRange = '${dateFormat.format(weekStart)} - ${dateFormat.format(weekEnd)}';

      // Get all users
      final usersSnapshot = await _firestore.collection('users').get();
      
      List<Map<String, dynamic>> leaderboardEntries = [];
      Map<String, String> userNames = {};

      for (var userDoc in usersSnapshot.docs) {
        final uid = userDoc.id;
        final username = userDoc.data()['username'] as String? ?? 'Unknown';
        userNames[uid] = username;
      }

      // Calculate points for each user
      for (var userDoc in usersSnapshot.docs) {
        final uid = userDoc.id;
        final username = userNames[uid] ?? 'Unknown';
        
        // Calculate points for this user
        final points = await _calculateUserPoints(uid, weekStart, weekEnd);
        
        leaderboardEntries.add({
          'username': username,
          'uid': uid,
          'gymPoints': points['gymTotal'] ?? 0,
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
      'gymRecords': 0,
      'gymDays': 0,
      'gymTotal': 0,
      'prayer': 0,
      'weight': 0,
      'total': 0,
    };

    try {
      final isCurrentUser = uid == FirebaseAuth.instance.currentUser?.uid;
      
      if (_debugMode && isCurrentUser) {
        final username = await _getUsername(uid);
        _debugInfo = '🔍 DEBUG FOR: $username\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        _debugInfo += '📅 Week: $_weekRange\n';
        _debugInfo += '📆 Week Start: ${DateFormat('MMM d, yyyy HH:mm').format(weekStart)}\n';
        _debugInfo += '📆 Week End: ${DateFormat('MMM d, yyyy HH:mm').format(weekEnd)}\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n';
        
        _debugData = {
          'username': username,
          'exercises': [],
          'gymDays': [],
          'records': [],
        };
      }

      // 1. GYM POINTS
      // Get ALL exercises for this user (all time) sorted by date
      final allExercisesSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('exercises')
          .orderBy('date')
          .get();

      // Track the previous weight for each exercise (from the last session)
      Map<String, double> previousWeights = {};
      
      // Track which exercises have already been counted this week
      Set<String> countedExercises = {};
      
      // Track unique gym days in the current week
      Set<String> gymDays = {};
      
      // Process all exercises in chronological order
      for (var doc in allExercisesSnapshot.docs) {
        final data = doc.data();
        final exerciseName = data['exerciseName'] as String? ?? '';
        final weight = (data['weight'] as num?)?.toDouble() ?? 0;
        final exerciseDate = data['date'] as Timestamp?;
        
        if (exerciseDate == null) continue;
        
        final exerciseDateTime = exerciseDate.toDate();
        String key = exerciseName.trim().toLowerCase();
        
        // Check if this exercise is within the current week
        final isInCurrentWeek = exerciseDateTime.compareTo(weekStart) >= 0 && 
                                exerciseDateTime.compareTo(weekEnd) < 0;
        
        // Track gym day if it's in the current week
        if (isInCurrentWeek) {
          final dateKey = DateFormat('yyyy-MM-dd').format(exerciseDateTime);
          gymDays.add(dateKey);
        }
        
        // Check if this exercise has been done before
        if (previousWeights.containsKey(key)) {
          final previousWeight = previousWeights[key]!;
          
          // If current weight is GREATER than previous weight, award points
          if (weight > previousWeight) {
            // Only count if the current exercise is within the current week
            // and we haven't counted this exercise yet this week
            if (isInCurrentWeek && !countedExercises.contains(key)) {
              points['gymRecords'] = (points['gymRecords'] ?? 0) + 2;
              countedExercises.add(key);
              
              if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
                _debugData['records'].add({
                  'exercise': exerciseName,
                  'oldWeight': previousWeight,
                  'newWeight': weight,
                  'increase': weight - previousWeight,
                  'date': DateFormat('MMM d').format(exerciseDateTime),
                });
              }
            }
          }
          
          // Update the previous weight for this exercise
          previousWeights[key] = weight;
        } else {
          // First time ever doing this exercise
          previousWeights[key] = weight;
        }
        
        // Store for debug (only for current week exercises)
        if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid && isInCurrentWeek) {
          _debugData['exercises'].add({
            'name': exerciseName,
            'weight': weight,
            'date': DateFormat('MMM d, HH:mm').format(exerciseDateTime),
            'previousWeight': previousWeights.containsKey(key) && previousWeights[key] != weight ? previousWeights[key] : null,
          });
        }
      }

      // Add gym day bonus: 2 points for each day with gym activity
      points['gymDays'] = gymDays.length * 2;
      
      // Calculate total gym points
      points['gymTotal'] = (points['gymRecords'] ?? 0) + (points['gymDays'] ?? 0);
      
      // Store gym days for debug
      if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
        _debugData['gymDays'] = gymDays.toList();
      }

      // 2. PRAYER POINTS
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

              if (inMosque) {
                points['prayer'] = (points['prayer'] ?? 0) + 5;
              } else if (onTime) {
                points['prayer'] = (points['prayer'] ?? 0) + 3;
              } else if (delayed) {
                points['prayer'] = (points['prayer'] ?? 0) + 1;
              } else {
                points['prayer'] = (points['prayer'] ?? 0) - 1;
              }
            }
          }
        }
      }

      // 3. WEIGHT POINTS
      final weightSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('weight')
          .where('date', isGreaterThanOrEqualTo: weekStart)
          .where('date', isLessThan: weekEnd)
          .orderBy('date')
          .get();

      if (weightSnapshot.docs.isNotEmpty) {
        final firstWeight = weightSnapshot.docs.first.data()['weight'] as num?;
        final lastWeight = weightSnapshot.docs.last.data()['weight'] as num?;
        
        if (firstWeight != null && lastWeight != null) {
          final weightLost = firstWeight.toDouble() - lastWeight.toDouble();
          if (weightLost > 0) {
            final pointsEarned = (weightLost * 10).floor();
            points['weight'] = (points['weight'] ?? 0) + pointsEarned;
          }
        }
      }

      // Calculate total points
      points['total'] = (points['gymTotal'] ?? 0) + 
                        (points['prayer'] ?? 0) + 
                        (points['weight'] ?? 0);
      
      // Build debug info
      if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
        _debugInfo += '🏋️ GYM SUMMARY:\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        _debugInfo += '📅 Gym Days: ${gymDays.length} day(s)\n';
        if (gymDays.isNotEmpty) {
          _debugInfo += '   ${gymDays.map((d) => DateFormat('EEEE, MMM d').format(DateTime.parse(d))).join('\n   ')}\n\n';
        } else {
          _debugInfo += '   No gym days this week\n\n';
        }
        
        _debugInfo += '📋 Exercise Progression (All Time):\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        
        // Group exercises by name to show progression
        Map<String, List<Map<String, dynamic>>> exerciseGroups = {};
        for (var ex in _debugData['exercises']) {
          final name = ex['name'];
          if (!exerciseGroups.containsKey(name)) {
            exerciseGroups[name] = [];
          }
          exerciseGroups[name]!.add(ex);
        }
        
        for (var entry in exerciseGroups.entries) {
          final exerciseName = entry.key;
          final sessions = entry.value;
          
          _debugInfo += '📌 $exerciseName:\n';
          for (var session in sessions) {
            _debugInfo += '   ${session['date']}: ${session['weight']}kg';
            if (session['previousWeight'] != null) {
              _debugInfo += ' (↑ +${session['weight'] - session['previousWeight']}kg)';
            }
            _debugInfo += '\n';
          }
        }
        _debugInfo += '\n';
        
        final recordsList = _debugData['records'] ?? [];
        _debugInfo += '🏆 Records Broken This Week: ${recordsList.length}\n';
        if (recordsList.isNotEmpty) {
          for (var record in recordsList) {
            _debugInfo += '   ✓ ${record['exercise']} (${record['date']}): ${record['oldWeight']}kg → ${record['newWeight']}kg (+${record['increase']}kg) (+2 points)\n';
          }
        } else {
          _debugInfo += '   No new records this week\n';
        }
        _debugInfo += '\n';
        _debugInfo += '📊 POINTS BREAKDOWN:\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        _debugInfo += '🏋️ Gym Records: ${points['gymRecords']} points\n';
        _debugInfo += '📅 Gym Days: ${points['gymDays']} points\n';
        _debugInfo += '🏋️ Gym Total: ${points['gymTotal']} points\n';
        _debugInfo += '🕌 Prayer: ${points['prayer']} points\n';
        _debugInfo += '⚖️ Weight: ${points['weight']} points\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        _debugInfo += '⭐ TOTAL: ${points['total']} points\n';
      }
      
      return points;
    } catch (e) {
      if (_debugMode) {
        _debugInfo += '❌ ERROR: $e\n';
      }
      points['total'] = (points['gymTotal'] ?? 0) + 
                        (points['prayer'] ?? 0) + 
                        (points['weight'] ?? 0);
      return points;
    }
  }

  Future<String> _getUsername(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data()?['username'] as String? ?? 'Unknown';
    } catch (e) {
      return 'Unknown';
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
          IconButton(
            icon: Icon(_debugMode ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () {
              setState(() {
                _debugMode = !_debugMode;
                if (_debugMode) {
                  _debugInfo = '🔄 Tap refresh to see debug info\n';
                } else {
                  _debugInfo = '';
                }
              });
            },
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
                // Debug info panel
                if (_debugMode && _debugInfo.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(
                      maxHeight: 400,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade800, width: 2),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _debugInfo,
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
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
                          const Text('🏋️ Gym: +2 for weight increase + 2 per gym day'),
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