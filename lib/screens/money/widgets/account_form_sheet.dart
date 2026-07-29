import 'package:flutter/material.dart';

class AccountFormResult {
  const AccountFormResult({
    required this.name,
    required this.color,
    required this.balance,
  });

  final String name;
  final Color color;
  final double balance;
}

const List<Color> kAccountColorSwatches = [
  Colors.green,
  Colors.purple,
  Colors.red,
  Colors.black,
  Colors.blue,
  Colors.orange,
  Colors.teal,
  Colors.pink,
  Colors.indigo,
  Colors.brown,
  Colors.cyan,
  Colors.amber,
];

/// Bottom sheet used both to create a brand-new money account (name, colour,
/// initial balance) and to edit an existing account's name/colour.
class AccountFormSheet extends StatefulWidget {
  const AccountFormSheet({
    super.key,
    this.initialName,
    this.initialColor,
    this.initialBalance,
  });

  /// When non-null, the sheet is in "edit" mode (no balance field, since
  /// balance is only ever adjusted through transactions).
  final String? initialName;
  final Color? initialColor;
  final double? initialBalance;

  @override
  State<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialName ?? '');
  late final TextEditingController _balanceCtrl = TextEditingController(
    text: (widget.initialBalance ?? 0).toStringAsFixed(2),
  );
  late Color _selectedColor = widget.initialColor ?? kAccountColorSwatches.first;

  bool get _isEditing => widget.initialName != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      AccountFormResult(
        name: _nameCtrl.text.trim(),
        color: _selectedColor,
        balance: double.tryParse(_balanceCtrl.text.trim()) ?? 0,
      ),
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
              _isEditing ? 'Edit Account' : 'New Money Account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              autofocus: !_isEditing,
              decoration: const InputDecoration(labelText: 'Account name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _balanceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Initial balance'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return double.tryParse(v.trim()) == null
                      ? 'Enter a valid number'
                      : null;
                },
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Colour', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in kAccountColorSwatches)
                  GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor.value == color.value
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _selectedColor.value == color.value
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: Text(_isEditing ? 'Save Changes' : 'Add Account'),
            ),
          ],
        ),
      ),
    );
  }
}