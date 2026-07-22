// weight_screen.dart - with only AppBar button (no FAB)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _RangeMode { weekly, monthly, yearly }

class _WeightPoint {
  final DateTime date;
  final double weight;
  _WeightPoint(this.date, this.weight);
}

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  _RangeMode _mode = _RangeMode.weekly;
  final _dateFmt = DateFormat('d MMM');

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('weights');

  String _docIdFor(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _addOrEditWeightDialog() async {
    DateTime selectedDate = DateTime.now();
    final weightCtrl = TextEditingController();

    // Pre-fill if an entry already exists for the chosen date.
    Future<void> refill(DateTime date) async {
      final doc = await _collection.doc(_docIdFor(date)).get();
      weightCtrl.text = doc.exists
          ? (doc.data()!['weight'] as num).toString()
          : '';
    }

    await refill(selectedDate);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Log weight'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(DateFormat('EEE, d MMM yyyy').format(selectedDate))),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          await refill(picked);
                          setLocalState(() => selectedDate = picked);
                        }
                      },
                      child: const Text('Change date'),
                    ),
                  ],
                ),
                TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight (kg)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final weight = double.tryParse(weightCtrl.text.trim());
                  if (weight == null) return;
                  await _collection.doc(_docIdFor(selectedDate)).set({
                    'date': Timestamp.fromDate(selectedDate),
                    'weight': weight,
                  });
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_mode) {
      case _RangeMode.weekly:
        return now.subtract(const Duration(days: 7));
      case _RangeMode.monthly:
        return DateTime(now.year, now.month - 1, now.day);
      case _RangeMode.yearly:
        return DateTime(now.year - 1, now.month, now.day);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weight'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Log weight',
            onPressed: _addOrEditWeightDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _collection.orderBy('date').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final allPoints = snapshot.data!.docs.map((d) {
              final data = d.data();
              return _WeightPoint(
                (data['date'] as Timestamp).toDate(),
                (data['weight'] as num).toDouble(),
              );
            }).toList();

            final points = allPoints
                .where((p) => p.date.isAfter(_rangeStart))
                .toList();

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<_RangeMode>(
                    segments: const [
                      ButtonSegment(
                          value: _RangeMode.weekly, label: Text('Weekly')),
                      ButtonSegment(
                          value: _RangeMode.monthly, label: Text('Monthly')),
                      ButtonSegment(
                          value: _RangeMode.yearly, label: Text('Yearly')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: points.isEmpty
                        ? const Center(
                            child: Text('No weight entries in this range yet.'),
                          )
                        : _WeightChart(points: points, dateFmt: _dateFmt),
                  ),
                  if (allPoints.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Latest: ${allPoints.last.weight.toStringAsFixed(1)} kg '
                      '(${DateFormat('d MMM yyyy').format(allPoints.last.date)})',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeightChart extends StatelessWidget {
  final List<_WeightPoint> points;
  final DateFormat dateFmt;
  const _WeightChart({required this.points, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].weight),
    ];
    final minY = points.map((p) => p.weight).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.weight).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 2 ? 2.0 : (maxY - minY) * 0.15;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: (points.length / 5).clamp(1, points.length).toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dateFmt.format(points[i].date),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            color: Theme.of(context).colorScheme.primary,
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }
}