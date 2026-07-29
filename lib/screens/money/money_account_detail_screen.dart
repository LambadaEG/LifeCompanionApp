import 'package:flutter/material.dart';

import '../../models/money_account.dart';
import '../../models/money_transaction.dart';
import '../../services/money_service.dart';
import 'widgets/account_form_sheet.dart';
import 'widgets/transaction_form_sheet.dart';

class MoneyAccountDetailScreen extends StatefulWidget {
  const MoneyAccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<MoneyAccountDetailScreen> createState() =>
      _MoneyAccountDetailScreenState();
}

class _MoneyAccountDetailScreenState extends State<MoneyAccountDetailScreen> {
  final _service = MoneyService();

  Future<void> _openAddTransactionSheet() async {
    final result = await showModalBottomSheet<TransactionFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TransactionFormSheet(),
    );
    if (result == null) return;
    await _service.addTransaction(
      accountId: widget.accountId,
      amount: result.amount,
      note: result.note,
      date: result.date,
    );
  }

  Future<void> _openEditTransactionSheet(MoneyTransaction tx) async {
    final result = await showModalBottomSheet<TransactionFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TransactionFormSheet(existing: tx),
    );
    if (result == null) return;
    await _service.editTransaction(
      accountId: widget.accountId,
      transactionId: tx.id,
      oldAmount: tx.amount,
      newAmount: result.amount,
      note: result.note,
      date: result.date,
    );
  }

  Future<void> _confirmDeleteTransaction(MoneyTransaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          'This removes "${tx.note.isEmpty ? tx.amount.toStringAsFixed(2) : tx.note}" '
          'and adjusts the account balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.deleteTransaction(
        accountId: widget.accountId,
        transactionId: tx.id,
        amount: tx.amount,
      );
    }
  }

  Future<void> _openEditAccountSheet(MoneyAccount account) async {
    final result = await showModalBottomSheet<AccountFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountFormSheet(
        initialName: account.name,
        initialColor: account.color,
      ),
    );
    if (result == null) return;
    await _service.updateAccount(
      accountId: widget.accountId,
      name: result.name,
      color: result.color,
    );
  }

  Future<void> _confirmDeleteAccount(MoneyAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          'This permanently deletes "${account.name}" and all of its transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.deleteAccount(widget.accountId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MoneyAccount>(
      stream: _service.streamAccount(widget.accountId),
      builder: (context, accountSnapshot) {
        final account = accountSnapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(account?.name ?? ''),
            backgroundColor: account?.color,
            foregroundColor:
                account != null ? _contrastingColor(account.color) : null,
            actions: [
              if (account != null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _openEditAccountSheet(account);
                    if (value == 'delete') _confirmDeleteAccount(account);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit account')),
                    PopupMenuItem(value: 'delete', child: Text('Delete account')),
                  ],
                ),
            ],
          ),
          body: account == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: account.color.withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          account.balance.toStringAsFixed(2),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StreamBuilder<List<MoneyTransaction>>(
                        stream: _service.streamTransactions(widget.accountId),
                        builder: (context, txSnapshot) {
                          if (txSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final txs = txSnapshot.data ?? [];
                          if (txs.isEmpty) {
                            return const Center(
                                child: Text('No transactions yet.'));
                          }
                          return ListView.builder(
                            itemCount: txs.length,
                            itemBuilder: (context, index) {
                              final tx = txs[index];
                              return Dismissible(
                                key: ValueKey(tx.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 20),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white),
                                ),
                                confirmDismiss: (_) async {
                                  await _confirmDeleteTransaction(tx);
                                  // The stream will remove the item once the
                                  // delete completes; never let Dismissible
                                  // remove it optimistically.
                                  return false;
                                },
                                child: ListTile(
                                  leading: Icon(
                                    tx.isIncome
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    color: tx.isIncome
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  title:
                                      Text(tx.note.isEmpty ? '(no note)' : tx.note),
                                  subtitle: Text(_formatDate(tx.date)),
                                  trailing: Text(
                                    '${tx.isIncome ? '+' : ''}${tx.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color:
                                          tx.isIncome ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onTap: () => _openEditTransactionSheet(tx),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
          floatingActionButton: account == null
              ? null
              : FloatingActionButton(
                  onPressed: _openAddTransactionSheet,
                  tooltip: 'Add transaction',
                  child: const Icon(Icons.add),
                ),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Color _contrastingColor(Color color) {
    return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}