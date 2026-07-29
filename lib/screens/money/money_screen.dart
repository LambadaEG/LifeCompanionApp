import 'package:flutter/material.dart';

import '../../models/money_account.dart';
import '../../services/money_service.dart';
import 'money_account_detail_screen.dart';
import 'widgets/account_form_sheet.dart';

class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  final _service = MoneyService();

  @override
  void initState() {
    super.initState();
    // Seeds Cash / Instapay / Vodafone Cash / Telda the first time this
    // user has no money accounts yet. No-op after that.
    _service.ensureDefaultAccounts();
  }

  Future<void> _openAddAccountSheet() async {
    final result = await showModalBottomSheet<AccountFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AccountFormSheet(),
    );
    if (result == null) return;
    await _service.addAccount(
      name: result.name,
      color: result.color,
      initialBalance: result.balance,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Money')),
      body: StreamBuilder<List<MoneyAccount>>(
        stream: _service.streamAccounts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data ?? [];
          if (accounts.isEmpty) {
            return const Center(
              child: Text('No accounts yet. Tap + to add one.'),
            );
          }

          final total = accounts.fold<double>(0, (sum, a) => sum + a.balance);

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      total.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              for (final account in accounts)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: account.color,
                        child: Text(
                          account.name.isNotEmpty
                              ? account.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(account.name),
                      subtitle: Text(account.balance.toStringAsFixed(2)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              MoneyAccountDetailScreen(accountId: account.id),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddAccountSheet,
        tooltip: 'Add account',
        child: const Icon(Icons.add),
      ),
    );
  }
}