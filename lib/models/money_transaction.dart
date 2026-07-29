import 'package:cloud_firestore/cloud_firestore.dart';

/// A single transaction under a money account, stored at:
/// users/{uid}/money_accounts/{accountId}/transactions/{transactionId}
///
/// [amount] is signed: positive = money in, negative = money out.
class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.amount,
    required this.note,
    required this.date,
  });

  final String id;
  final double amount;
  final String note;
  final DateTime date;

  bool get isIncome => amount >= 0;

  factory MoneyTransaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final ts = data['date'];
    return MoneyTransaction(
      id: doc.id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      note: data['note'] as String? ?? '',
      date: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}