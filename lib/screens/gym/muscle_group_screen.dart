import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/exercise_entry.dart';

class MuscleGroupScreen extends StatefulWidget {
  final String muscleGroup;
  const MuscleGroupScreen({super.key, required this.muscleGroup});

  @override
  State<MuscleGroupScreen> createState() => _MuscleGroupScreenState();
}

class _MuscleGroupScreenState extends State<MuscleGroupScreen> {
  final _dateFmt = DateFormat('EEE, d MMM yyyy');
  final _shortDateFmt = DateFormat('d MMM');
  final _weekdayFmt = DateFormat('EEE');
  bool _isAddingColumn = false;
  bool _fabMenuOpen = false;
  final ScrollController _horizontalScrollController = ScrollController();

  // ---------------------------------------------------------------------
  // Design tokens
  // ---------------------------------------------------------------------
  static const double _nameColWidth = 180;
  static const double _dateColWidth = 92;
  static const double _rowHeight = 56;
  static const double _headerHeight = 64;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('exercises');

  // ---------------------------------------------------------------------
  // Data mutation methods (unchanged logic)
  // ---------------------------------------------------------------------

  Future<void> _addExerciseDialog() async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return _StyledDialog(
          icon: Icons.fitness_center_rounded,
          title: 'Add exercise',
          subtitle: widget.muscleGroup,
          content: TextField(
            controller: nameCtrl,
            decoration: _fieldDecoration('Exercise name', Icons.edit_rounded),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) {
              if (nameCtrl.text.trim().isNotEmpty) {
                Navigator.pop(context, nameCtrl.text.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  _showSnack('Please enter an exercise name', isError: true);
                  return;
                }
                Navigator.pop(context, name);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        );
      },
    ).then((exerciseName) async {
      if (exerciseName != null && exerciseName is String && exerciseName.isNotEmpty) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);

        final entry = ExerciseEntry(
          id: '',
          exerciseName: exerciseName,
          weight: 0.0,
          reps: null,
          date: todayDate,
        );

        try {
          await _collection.add(
            entry.toMap(muscleGroup: widget.muscleGroup),
          );
          _showSnack('Added "$exerciseName" to ${widget.muscleGroup}');
        } catch (e) {
          _showSnack('Failed to add exercise: $e', isError: true);
        }
      }
    });
  }

  Future<void> _editExerciseName(String oldName, String newName) async {
    if (oldName == newName.trim()) return;

    try {
      final snapshot = await _collection
          .where('muscleGroup', isEqualTo: widget.muscleGroup)
          .where('exerciseName', isEqualTo: oldName)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'exerciseName': newName.trim()});
      }
      await batch.commit();

      _showSnack('Updated exercise name to "$newName"');
    } catch (e) {
      _showSnack('Failed to update exercise name: $e', isError: true);
    }
  }

  Future<void> _editDateForColumn(DateTime oldDate, DateTime newDate) async {
    if (oldDate.year == newDate.year &&
        oldDate.month == newDate.month &&
        oldDate.day == newDate.day) return;

    try {
      final snapshot = await _collection
          .where('muscleGroup', isEqualTo: widget.muscleGroup)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int updatedCount = 0;

      for (var doc in snapshot.docs) {
        final docData = doc.data();
        final docDate = (docData['date'] as Timestamp).toDate();

        if (docDate.year == oldDate.year &&
            docDate.month == oldDate.month &&
            docDate.day == oldDate.day) {
          batch.update(doc.reference, {'date': Timestamp.fromDate(newDate)});
          updatedCount++;
        }
      }

      if (updatedCount == 0) {
        _showSnack('No entries found for this date', isWarning: true);
        return;
      }

      await batch.commit();

      _showSnack('Updated $updatedCount entries to ${_dateFmt.format(newDate)}');
    } catch (e) {
      _showSnack('Failed to update date: $e', isError: true);
    }
  }

  Future<void> _addWeightForDate(String exerciseName, DateTime date, double weight) async {
    final entry = ExerciseEntry(
      id: '',
      exerciseName: exerciseName,
      weight: weight,
      reps: null,
      date: date,
    );
    await _collection.add(
      entry.toMap(muscleGroup: widget.muscleGroup),
    );
  }

  Future<void> _editWeight(String entryId, double newWeight) async {
    try {
      await _collection.doc(entryId).update({
        'weight': newWeight,
      });
    } catch (e) {
      _showSnack('Failed to update weight: $e', isError: true);
    }
  }

  Future<void> _showEditWeightDialog({
    String? entryId,
    String? exerciseName,
    DateTime? date,
    double? currentWeight,
    bool isNew = false,
  }) async {
    final weightCtrl = TextEditingController(
      text: currentWeight != null ? currentWeight.toStringAsFixed(1) : '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return _StyledDialog(
          icon: Icons.monitor_weight_rounded,
          title: isNew ? 'Add weight' : 'Edit weight',
          subtitle: (isNew && exerciseName != null && date != null)
              ? '$exerciseName · ${_dateFmt.format(date)}'
              : null,
          content: TextField(
            controller: weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDecoration('Weight (kg)', Icons.monitor_weight_outlined),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final newWeight = double.tryParse(weightCtrl.text.trim());
                if (newWeight == null) {
                  _showSnack('Please enter a valid weight', isError: true);
                  return;
                }
                if (isNew && exerciseName != null && date != null) {
                  await _addWeightForDate(exerciseName, date, newWeight);
                } else if (entryId != null) {
                  await _editWeight(entryId, newWeight);
                }
                if (context.mounted) Navigator.pop(context);
              },
              icon: Icon(isNew ? Icons.add_rounded : Icons.check_rounded, size: 18),
              label: Text(isNew ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNewColumnForDate({DateTime? date}) async {
    if (_isAddingColumn) return;

    DateTime targetDate;
    if (date == null) {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (picked == null) return;
      targetDate = DateTime(picked.year, picked.month, picked.day);
    } else {
      targetDate = date;
    }

    setState(() {
      _isAddingColumn = true;
    });

    try {
      final snapshot = await _collection
          .where('muscleGroup', isEqualTo: widget.muscleGroup)
          .get();

      final entries = snapshot.docs.map(ExerciseEntry.fromDoc).toList();

      final existingDate = entries.any((e) =>
        e.date.year == targetDate.year &&
        e.date.month == targetDate.month &&
        e.date.day == targetDate.day
      );

      if (existingDate) {
        _showSnack('Column for ${_dateFmt.format(targetDate)} already exists!',
            isWarning: true);
        setState(() {
          _isAddingColumn = false;
        });
        return;
      }

      final exerciseNames = entries.map((e) => e.exerciseName).toSet().toList();

      int addedCount = 0;
      for (var exerciseName in exerciseNames) {
        final exerciseEntries = entries
            .where((e) => e.exerciseName == exerciseName)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        if (exerciseEntries.isNotEmpty) {
          final latestWeight = exerciseEntries.first.weight;
          await _addWeightForDate(exerciseName, targetDate, latestWeight);
          addedCount++;
        }
      }

      _showSnack('Added column for ${_dateFmt.format(targetDate)} with $addedCount exercises');
    } catch (e) {
      _showSnack('Failed to add column: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isAddingColumn = false;
        });
      }
    }
  }

  Future<void> _addNewColumn(List<ExerciseEntry> entries) async {
    if (_isAddingColumn) return;

    setState(() {
      _isAddingColumn = true;
    });

    try {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      final existingToday = entries.any((e) =>
        e.date.year == todayDate.year &&
        e.date.month == todayDate.month &&
        e.date.day == todayDate.day
      );

      if (existingToday) {
        _showSnack('Today\'s column already exists!', isWarning: true);
        setState(() {
          _isAddingColumn = false;
        });
        return;
      }

      final exerciseNames = entries.map((e) => e.exerciseName).toSet().toList();

      int addedCount = 0;
      for (var exerciseName in exerciseNames) {
        final exerciseEntries = entries
            .where((e) => e.exerciseName == exerciseName)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        if (exerciseEntries.isNotEmpty) {
          final latestWeight = exerciseEntries.first.weight;
          await _addWeightForDate(exerciseName, todayDate, latestWeight);
          addedCount++;
        }
      }

      _showSnack('Added new column for today with $addedCount exercises');
    } catch (e) {
      _showSnack('Failed to add new column: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isAddingColumn = false;
        });
      }
    }
  }

  Future<void> _deleteExercise(String exerciseName) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => _StyledDialog(
        icon: Icons.delete_outline_rounded,
        iconColor: Colors.red,
        title: 'Delete exercise',
        content: Text('Are you sure you want to delete all entries for "$exerciseName"? This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.12),
              foregroundColor: Colors.red.shade700,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        final snapshot = await _collection
            .where('muscleGroup', isEqualTo: widget.muscleGroup)
            .where('exerciseName', isEqualTo: exerciseName)
            .get();

        final batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        _showSnack('Deleted "$exerciseName"');
      } catch (e) {
        _showSnack('Failed to delete exercise: $e', isError: true);
      }
    }
  }

  Future<void> _deleteColumn(DateTime date) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => _StyledDialog(
        icon: Icons.delete_outline_rounded,
        iconColor: Colors.red,
        title: 'Delete column',
        content: Text('Are you sure you want to delete all entries for ${_dateFmt.format(date)}? This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.12),
              foregroundColor: Colors.red.shade700,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        final snapshot = await _collection
            .where('muscleGroup', isEqualTo: widget.muscleGroup)
            .get();

        final batch = FirebaseFirestore.instance.batch();
        int deletedCount = 0;

        for (var doc in snapshot.docs) {
          final docData = doc.data();
          final docDate = (docData['date'] as Timestamp).toDate();

          if (docDate.year == date.year &&
              docDate.month == date.month &&
              docDate.day == date.day) {
            batch.delete(doc.reference);
            deletedCount++;
          }
        }

        if (deletedCount == 0) {
          _showSnack('No entries found for this date', isWarning: true);
          return;
        }

        await batch.commit();

        _showSnack('Deleted $deletedCount entries for ${_dateFmt.format(date)}');
      } catch (e) {
        _showSnack('Failed to delete column: $e', isError: true);
      }
    }
  }

  Future<void> _showEditExerciseNameDialog(String currentName) async {
    final nameCtrl = TextEditingController(text: currentName);

    await showDialog(
      context: context,
      builder: (context) => _StyledDialog(
        icon: Icons.edit_rounded,
        title: 'Rename exercise',
        content: TextField(
          controller: nameCtrl,
          decoration: _fieldDecoration('Exercise name', Icons.fitness_center_rounded),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) {
                _showSnack('Please enter a name', isError: true);
                return;
              }
              Navigator.pop(context, newName);
            },
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    ).then((newName) async {
      if (newName != null && newName is String && newName.isNotEmpty) {
        await _editExerciseName(currentName, newName);
      }
    });
  }

  Future<void> _showEditDateDialog(DateTime currentDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      final newDate = DateTime(picked.year, picked.month, picked.day);
      await _editDateForColumn(currentDate, newDate);
    }
  }

  // ---------------------------------------------------------------------
  // Small UI helpers
  // ---------------------------------------------------------------------

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  void _showSnack(String message, {bool isError = false, bool isWarning = false}) {
    if (!mounted) return;
    final color = isError
        ? Colors.red.shade600
        : isWarning
            ? Colors.orange.shade700
            : Colors.green.shade600;
    final icon = isError
        ? Icons.error_outline_rounded
        : isWarning
            ? Icons.warning_amber_rounded
            : Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          widget.muscleGroup,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _addExerciseDialog,
            tooltip: 'Add new exercise',
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _buildFabMenu(),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _collection
              .where('muscleGroup', isEqualTo: widget.muscleGroup)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorState(message: '${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return _EmptyState(
                muscleGroup: widget.muscleGroup,
                onAdd: _addExerciseDialog,
              );
            }

            final entries = docs.map(ExerciseEntry.fromDoc).toList();

            final dates = entries.map((e) => e.date).toSet().toList()
              ..sort((a, b) => a.compareTo(b));

            final exerciseNames = entries.map((e) => e.exerciseName).toSet().toList()
              ..sort();

            final Map<String, Map<DateTime, Map<String, dynamic>>> exerciseData = {};
            for (var entry in entries) {
              exerciseData.putIfAbsent(entry.exerciseName, () => {});
              exerciseData[entry.exerciseName]![entry.date] = {
                'weight': entry.weight,
                'id': entry.id,
              };
            }

            final displayDates = dates.take(10).toList();

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryStrip(exerciseNames.length, displayDates.length),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _buildTable(
                      context,
                      exerciseNames: exerciseNames,
                      displayDates: displayDates,
                      exerciseData: exerciseData,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryStrip(int exerciseCount, int columnCount) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _SummaryChip(
          icon: Icons.fitness_center_rounded,
          label: '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
          color: scheme.primary,
        ),
        const SizedBox(width: 8),
        _SummaryChip(
          icon: Icons.view_column_rounded,
          label: '$columnCount session${columnCount == 1 ? '' : 's'}',
          color: Colors.teal,
        ),
        const Spacer(),
        Icon(Icons.swipe_rounded, size: 16, color: scheme.outline),
        const SizedBox(width: 4),
        Text(
          'Swipe to scroll',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      ],
    );
  }

  Widget _buildTable(
    BuildContext context, {
    required List<String> exerciseNames,
    required List<DateTime> displayDates,
    required Map<String, Map<DateTime, Map<String, dynamic>>> exerciseData,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frozen first column - Exercise names
          SizedBox(
            width: _nameColWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: _headerHeight,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Text(
                    'Exercise',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                ...exerciseNames.asMap().entries.map((entry) {
                  final i = entry.key;
                  final exerciseName = entry.value;
                  return Container(
                    height: _rowHeight,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: i.isEven
                        ? Colors.transparent
                        : scheme.surfaceContainerHighest.withOpacity(0.35),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onDoubleTap: () => _showEditExerciseNameDialog(exerciseName),
                            child: Text(
                              exerciseName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _deleteExercise(exerciseName),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          Container(width: 1, color: scheme.outlineVariant.withOpacity(0.5)),

          // Scrollable columns - Dates and weights
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Headers row
                  Container(
                    height: _headerHeight,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      border: Border(
                        bottom: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: displayDates.map((date) {
                        final isToday = date.year == today.year &&
                            date.month == today.month &&
                            date.day == today.day;
                        return SizedBox(
                          width: _dateColWidth,
                          child: InkWell(
                            onDoubleTap: () => _showEditDateDialog(date),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _weekdayFmt.format(date).toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.4,
                                            color: isToday
                                                ? scheme.primary
                                                : scheme.onPrimaryContainer.withOpacity(0.6),
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => _deleteColumn(date),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 14,
                                            color: scheme.outline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _shortDateFmt.format(date),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isToday
                                          ? scheme.primary
                                          : scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Data rows
                  ...exerciseNames.asMap().entries.map((rowEntry) {
                    final rowIndex = rowEntry.key;
                    final exerciseName = rowEntry.value;
                    final dateMap = exerciseData[exerciseName] ?? {};

                    // compute trend vs previous displayed value for coloring
                    double? prevWeight;

                    return Container(
                      height: _rowHeight,
                      color: rowIndex.isEven
                          ? Colors.transparent
                          : scheme.surfaceContainerHighest.withOpacity(0.35),
                      child: Row(
                        children: displayDates.map((date) {
                          final data = dateMap[date];
                          final weight = data?['weight'] as double?;
                          final entryId = data?['id'] as String?;

                          Color? chipColor;
                          IconData? trendIcon;
                          if (weight != null && weight > 0) {
                            if (prevWeight != null) {
                              if (weight > prevWeight!) {
                                chipColor = Colors.green;
                                trendIcon = Icons.trending_up_rounded;
                              } else if (weight < prevWeight!) {
                                chipColor = Colors.orange;
                                trendIcon = Icons.trending_down_rounded;
                              }
                            }
                            prevWeight = weight;
                          }

                          return SizedBox(
                            width: _dateColWidth,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    if (entryId != null && weight != null) {
                                      _showEditWeightDialog(
                                        entryId: entryId,
                                        currentWeight: weight,
                                      );
                                    } else {
                                      _showEditWeightDialog(
                                        exerciseName: exerciseName,
                                        date: date,
                                        isNew: true,
                                      );
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: weight != null
                                          ? scheme.primary.withOpacity(0.10)
                                          : scheme.surfaceContainerHighest.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                      border: weight == null
                                          ? Border.all(
                                              color: scheme.outline.withOpacity(0.25),
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    child: Center(
                                      child: weight != null
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                if (trendIcon != null) ...[
                                                  Icon(trendIcon, size: 12, color: chipColor),
                                                  const SizedBox(width: 2),
                                                ],
                                                Text(
                                                  weight.toStringAsFixed(1),
                                                  style: TextStyle(
                                                    color: scheme.primary,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13.5,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Icon(
                                              Icons.add_rounded,
                                              size: 18,
                                              color: scheme.outline,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFabMenu() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          offset: _fabMenuOpen ? Offset.zero : const Offset(0, 0.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _fabMenuOpen ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_fabMenuOpen,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MiniAction(
                      label: 'Add past day\'s column',
                      icon: Icons.calendar_month_rounded,
                      color: scheme.secondary,
                      onTap: () {
                        setState(() => _fabMenuOpen = false);
                        _addNewColumnForDate();
                      },
                    ),
                    const SizedBox(height: 10),
                    _MiniAction(
                      label: 'Add today\'s column',
                      icon: Icons.today_rounded,
                      color: scheme.primary,
                      onTap: () {
                        setState(() => _fabMenuOpen = false);
                        _collection
                            .where('muscleGroup', isEqualTo: widget.muscleGroup)
                            .get()
                            .then((snapshot) {
                          final entries =
                              snapshot.docs.map(ExerciseEntry.fromDoc).toList();
                          _addNewColumn(entries);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: _isAddingColumn
              ? null
              : () => setState(() => _fabMenuOpen = !_fabMenuOpen),
          child: _isAddingColumn
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _fabMenuOpen ? 0.125 : 0,
                  child: const Icon(Icons.add_rounded),
                ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Small reusable presentational widgets
// ===========================================================================

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SummaryChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MiniAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: label,
          backgroundColor: color,
          onPressed: onTap,
          child: Icon(icon, color: Colors.white),
        ),
      ],
    );
  }
}

class _StyledDialog extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;

  const _StyledDialog({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = iconColor ?? scheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
            const SizedBox(height: 18),
            content,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions
                  .map((w) => Padding(padding: const EdgeInsets.only(left: 8), child: w))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String muscleGroup;
  final VoidCallback onAdd;
  const _EmptyState({required this.muscleGroup, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.fitness_center_rounded, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No exercises yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first $muscleGroup exercise to start tracking progress over time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add exercise'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text('Something went wrong', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}