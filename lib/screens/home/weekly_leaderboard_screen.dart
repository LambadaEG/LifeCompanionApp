// weekly_leaderboard_screen.dart - updated to show all users
import 'package:adhan_dart/adhan_dart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:LifeCompanion/services/auth_service.dart';
import 'package:geolocator/geolocator.dart';
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
  
  // Cache for prayer times
  Map<String, Map<String, DateTime>> _prayerTimesCache = {};

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
    _prayerTimesCache = {};

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

  Future<Map<String, DateTime>> _getPrayerTimesForDate(DateTime date, String uid) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    
    // Check cache first
    if (_prayerTimesCache.containsKey(dateKey)) {
      return _prayerTimesCache[dateKey]!;
    }
    
    try {
      // Get user's location from their profile
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data();
      
      if (userData == null) {
        throw Exception('User data not found');
      }
      
      // Get location from user profile
      final latitude = userData['latitude'] as double?;
      final longitude = userData['longitude'] as double?;
      
      if (latitude == null || longitude == null) {
        throw Exception('User location not set');
      }
      
      final coordinates = Coordinates(latitude, longitude);
      final params = CalculationMethodParameters.muslimWorldLeague();
      
      final prayerTimes = PrayerTimes(
        coordinates: coordinates,
        date: date,
        calculationParameters: params,
      );
      
      final prayerTimesMap = {
        'fajr': prayerTimes.fajr,
        'dhuhr': prayerTimes.dhuhr,
        'asr': prayerTimes.asr,
        'maghrib': prayerTimes.maghrib,
        'isha': prayerTimes.isha,
      };
      
      // Cache the result
      _prayerTimesCache[dateKey] = prayerTimesMap;
      
      return prayerTimesMap;
    } catch (e) {
      // Fallback to approximate times if location not available
      final fallbackTimes = {
        'fajr': DateTime(date.year, date.month, date.day, 5, 0),
        'dhuhr': DateTime(date.year, date.month, date.day, 12, 0),
        'asr': DateTime(date.year, date.month, date.day, 15, 0),
        'maghrib': DateTime(date.year, date.month, date.day, 18, 0),
        'isha': DateTime(date.year, date.month, date.day, 20, 0),
      };
      
      _prayerTimesCache[dateKey] = fallbackTimes;
      return fallbackTimes;
    }
  }

  Future<Map<String, int>> _calculateUserPoints(String uid, DateTime weekStart, DateTime weekEnd) async {
    Map<String, int> points = {
      'gymRecords': 0,
      'gymDays': 0,
      'gymTotal': 0,
      'prayer': 0,
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

      // 2. PRAYER POINTS - WITH DYNAMIC PRAYER TIMES
      List<String> prayerNames = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
      
      // Get all dates from weekStart to today (or weekEnd if weekEnd is in the past)
      List<String> weekDates = [];
      DateTime current = weekStart;
      final now = DateTime.now();
      final endDate = weekEnd.isBefore(now) ? weekEnd : now;
      
      while (current.isBefore(endDate)) {
        weekDates.add(DateFormat('yyyy-MM-dd').format(current));
        current = current.add(const Duration(days: 1));
      }
      
      // For debug tracking
      Map<String, Map<String, dynamic>> prayerDebug = {};
      
      // Process each day's prayers
      for (String date in weekDates) {
        final docSnapshot = await _firestore
            .collection('users')
            .doc(uid)
            .collection('prayers')
            .doc(date)
            .get();
        
        final data = docSnapshot.data();
        
        // Parse the date
        final dateObj = DateTime.parse(date);
        final isToday = DateFormat('yyyy-MM-dd').format(now) == date;
        
        // Get prayer times for this date
        Map<String, DateTime> prayerTimes;
        try {
          prayerTimes = await _getPrayerTimesForDate(dateObj, uid);
        } catch (e) {
          // Fallback times if we can't get prayer times
          prayerTimes = {
            'fajr': DateTime(dateObj.year, dateObj.month, dateObj.day, 5, 0),
            'dhuhr': DateTime(dateObj.year, dateObj.month, dateObj.day, 12, 0),
            'asr': DateTime(dateObj.year, dateObj.month, dateObj.day, 15, 0),
            'maghrib': DateTime(dateObj.year, dateObj.month, dateObj.day, 18, 0),
            'isha': DateTime(dateObj.year, dateObj.month, dateObj.day, 20, 0),
          };
        }
        
        // For each prayer, check if it has passed
        for (String prayerName in prayerNames) {
          // Check if this prayer has already passed for today
          bool prayerPassed = true;
          if (isToday) {
            final prayerTime = prayerTimes[prayerName]!;
            // If the prayer time hasn't passed yet, skip it
            if (now.isBefore(prayerTime)) {
              prayerPassed = false;
            }
          }
          
          // Only process if this prayer has passed
          if (!prayerPassed) {
            continue;
          }
          
          if (data != null && data.containsKey(prayerName)) {
            final prayerData = data[prayerName] as Map<String, dynamic>?;
            if (prayerData != null) {
              final onTime = prayerData['onTime'] == true;
              final delayed = prayerData['delayed'] == true;
              final inMosque = prayerData['inMosque'] == true;

              // Prayer was logged - check the conditions
              if (inMosque) {
                points['prayer'] = (points['prayer'] ?? 0) + 5;
                if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
                  prayerDebug[date] ??= {};
                  prayerDebug[date]![prayerName] = '🕌 In Mosque: +5';
                }
              } else if (onTime) {
                points['prayer'] = (points['prayer'] ?? 0) + 3;
                if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
                  prayerDebug[date] ??= {};
                  prayerDebug[date]![prayerName] = '⏰ On Time: +3';
                }
              } else if (delayed) {
                points['prayer'] = (points['prayer'] ?? 0) + 1;
                if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
                  prayerDebug[date] ??= {};
                  prayerDebug[date]![prayerName] = '⏳ Delayed: +1';
                }
              }
              // If none of the above, it was missed (logged as false)
              else {
                points['prayer'] = (points['prayer'] ?? 0) - 1;
                if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
                  prayerDebug[date] ??= {};
                  prayerDebug[date]![prayerName] = '❌ Missed: -1';
                }
              }
            }
          } else {
            // No data for this prayer on this date = MISSED
            points['prayer'] = (points['prayer'] ?? 0) - 1;
            if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
              prayerDebug[date] ??= {};
              prayerDebug[date]![prayerName] = '❌ Missed (no data): -1';
            }
          }
        }
      }

      // Add prayer debug info
      if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
        _debugInfo += '🕌 PRAYER SUMMARY:\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        
        if (prayerDebug.isEmpty) {
          _debugInfo += 'No prayer data available\n\n';
        } else {
          // Sort dates
          final sortedDates = prayerDebug.keys.toList()..sort();
          for (var date in sortedDates) {
            _debugInfo += '📅 ${DateFormat('EEEE, MMM d').format(DateTime.parse(date))}:\n';
            final prayers = prayerDebug[date]!;
            for (var prayerName in prayerNames) {
              if (prayers.containsKey(prayerName)) {
                _debugInfo += '   ${prayerName.toUpperCase()}: ${prayers[prayerName]}\n';
              }
            }
            _debugInfo += '\n';
          }
        }
      }

      // Calculate total points (gym + prayer only)
      points['total'] = (points['gymTotal'] ?? 0) + (points['prayer'] ?? 0);
      
      // Build debug info
      if (_debugMode && uid == FirebaseAuth.instance.currentUser?.uid) {
        _debugInfo += '📊 POINTS BREAKDOWN:\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        _debugInfo += '🏋️ Gym Records: ${points['gymRecords']} points\n';
        _debugInfo += '📅 Gym Days: ${points['gymDays']} points\n';
        _debugInfo += '🏋️ Gym Total: ${points['gymTotal']} points\n';
        _debugInfo += '🕌 Prayer: ${points['prayer']} points\n';
        _debugInfo += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        _debugInfo += '⭐ TOTAL: ${points['total']} points\n';
      }
      
      return points;
    } catch (e) {
      if (_debugMode) {
        _debugInfo += '❌ ERROR: $e\n';
      }
      points['total'] = (points['gymTotal'] ?? 0) + (points['prayer'] ?? 0);
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
                          const Text('🏋️ Gym: +2 per gym day'),
                          const Text('📈 Gym: +2 for weight increase'),
                          const Text('🕌 Prayer in Mosque: +5'),
                          const Text('⏰ Prayer on time: +3'),
                          const Text('⏳ Prayer delayed: +1'),
                          const Text('❌ Prayer missed: -1'),
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