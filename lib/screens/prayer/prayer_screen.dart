import 'package:adhan_dart/adhan_dart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class _PrayerRow {
  final String key; // fajr, dhuhr, asr, maghrib, isha
  final String label;
  final DateTime time;

  _PrayerRow(this.key, this.label, this.time);
}

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  final _timeFmt = DateFormat('h:mm a');
  final _dateFmt = DateFormat('EEEE, d MMM yyyy');

  bool _loadingLocation = true;
  String? _locationError;
  List<_PrayerRow> _prayers = [];
  
  // Track current date being viewed
  DateTime _currentDate = DateTime.now();

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  String get _todayId => DateFormat('yyyy-MM-dd').format(_currentDate);

  DocumentReference<Map<String, dynamic>> get _todayDoc =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('prayers')
          .doc(_todayId);

  @override
  void initState() {
    super.initState();
    _loadPrayerTimes();
  }

  Future<void> _loadPrayerTimes() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied.');
      }

      final pos = await Geolocator.getCurrentPosition();

      final coordinates = Coordinates(
        pos.latitude,
        pos.longitude,
      );

      final params = CalculationMethodParameters.muslimWorldLeague();

      final prayerTimes = PrayerTimes(
        coordinates: coordinates,
        date: _currentDate,
        calculationParameters: params,
      );

      if (!mounted) return;

      setState(() {
        _prayers = [
          _PrayerRow('fajr', 'Fajr', prayerTimes.fajr.add(const Duration(hours: 3))),
          _PrayerRow('dhuhr', 'Dhuhr', prayerTimes.dhuhr.add(const Duration(hours: 3))),
          _PrayerRow('asr', 'Asr', prayerTimes.asr.add(const Duration(hours: 3))),
          _PrayerRow('maghrib', 'Maghrib', prayerTimes.maghrib.add(const Duration(hours: 3))),
          _PrayerRow('isha', 'Isha', prayerTimes.isha.add(const Duration(hours: 3))),
        ];

        _loadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _locationError = e.toString();
        _loadingLocation = false;
      });
    }
  }

  Future<void> _setPrayerStatus(
    String prayerKey, {
    bool? onTime,
    bool? delayed,
  }) async {
    final prayerData = <String, dynamic>{};

    if (onTime != null) {
      prayerData['onTime'] = onTime;

      if (onTime) {
        prayerData['delayed'] = false;
      }
    }

    if (delayed != null) {
      prayerData['delayed'] = delayed;

      if (delayed) {
        prayerData['onTime'] = false;
      }
    }

    final update = <String, dynamic>{
      prayerKey: prayerData,
    };

    try {
      await _todayDoc.set(
        update,
        SetOptions(merge: true),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Failed to save status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  void _goToPreviousDay() {
    setState(() {
      _currentDate = _currentDate.subtract(const Duration(days: 1));
      _prayers = [];
      _loadingLocation = true;
    });
    _loadPrayerTimes();
  }

  void _goToNextDay() {
    setState(() {
      _currentDate = _currentDate.add(const Duration(days: 1));
      _prayers = [];
      _loadingLocation = true;
    });
    _loadPrayerTimes();
  }

  void _goToToday() {
    setState(() {
      _currentDate = DateTime.now();
      _prayers = [];
      _loadingLocation = true;
    });
    _loadPrayerTimes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: _goToToday,
            tooltip: 'Go to today',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPrayerTimes,
          ),
        ],
      ),
      body: SafeArea(
        child: _loadingLocation
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : _locationError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _locationError!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _loadPrayerTimes,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : GestureDetector(
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity! > 0) {
                        _goToPreviousDay();
                      } else if (details.primaryVelocity! < 0) {
                        _goToNextDay();
                      }
                    },
                    child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _todayDoc.snapshots(),
                      builder: (context, snapshot) {
                        final data = snapshot.data?.data() ?? {};

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_ios),
                                  onPressed: _goToPreviousDay,
                                  tooltip: 'Previous day',
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      _dateFmt.format(_currentDate),
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios),
                                  onPressed: _goToNextDay,
                                  tooltip: 'Next day',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Card(
                              elevation: 0,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: DataTable(
                                  columnSpacing: 16,
                                  columns: const [
                                    DataColumn(
                                      label: Text('Prayer'),
                                    ),
                                    DataColumn(
                                      label: Text('Time'),
                                    ),
                                    DataColumn(
                                      label: Text('On time'),
                                    ),
                                    DataColumn(
                                      label: Text('Delayed'),
                                    ),
                                  ],
                                  rows: _prayers.map((p) {
                                    final prayerData = data[p.key] as Map<String, dynamic>?;
                                    
                                    final onTime = prayerData?['onTime'] == true;
                                    final delayed = prayerData?['delayed'] == true;

                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Text(p.label),
                                        ),
                                        DataCell(
                                          Text(
                                            _timeFmt.format(p.time),
                                          ),
                                        ),
                                        DataCell(
                                          Checkbox(
                                            value: onTime,
                                            onChanged: (v) async {
                                              await _setPrayerStatus(
                                                p.key,
                                                onTime: v,
                                              );
                                              
                                              if (mounted) {
                                                setState(() {});
                                              }
                                            },
                                          ),
                                        ),
                                        DataCell(
                                          Checkbox(
                                            value: delayed,
                                            onChanged: (v) async {
                                              await _setPrayerStatus(
                                                p.key,
                                                delayed: v,
                                              );
                                              
                                              if (mounted) {
                                                setState(() {});
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            if (_prayers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text('No prayer times available'),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}