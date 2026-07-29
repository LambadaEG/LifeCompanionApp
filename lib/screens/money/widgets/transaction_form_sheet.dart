import 'package:flutter/material.dart';

import '../../../models/money_transaction.dart';

class TransactionFormResult {
  const TransactionFormResult({
    required this.amount,
    required this.note,
    required this.date,
  });

  /// Signed amount: positive = money in, negative = money out.
  final double amount;
  final String note;
  final DateTime date;
}

/// Bottom sheet used both to add a new transaction and to edit an existing
/// one. The user picks "money in" / "money out" plus a positive amount; the
/// sheet itself takes care of turning that into the signed amount that the
/// service expects.
class TransactionFormSheet extends StatefulWidget {
  const TransactionFormSheet({super.key, this.existing});

  final MoneyTransaction? existing;

  @override
  State<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl = TextEditingController(
    text: widget.existing != null
        ? widget.existing!.amount.abs().toStringAsFixed(2)
        : '',
  );
  late final TextEditingController _noteCtrl =
      TextEditingController(text: widget.existing?.note ?? '');
  late bool _isIncome = widget.existing?.isIncome ?? true;
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final raw = double.parse(_amountCtrl.text.trim());
    final signed = _isIncome ? raw.abs() : -raw.abs();
    Navigator.of(context).pop(
      TransactionFormResult(amount: signed, note: _noteCtrl.text.trim(), date: _date),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit Transaction' : 'New Transaction',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Money in'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Money out'),
                  icon: Icon(Icons.arrow_upward),
                ),
              ],
              selected: {_isIncome},
              onSelectionChanged: (s) => setState(() => _isIncome = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter an amount';
                final n = double.tryParse(v.trim());
                if (n == null) return 'Enter a valid number';
                if (n <= 0) return 'Amount must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: Text(_isEditing ? 'Save Changes' : 'Add Transaction'),
            ),
          ],
        ),
      ),
    );
  }
}