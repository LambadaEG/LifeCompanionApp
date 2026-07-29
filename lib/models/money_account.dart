import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// A single money account (Cash, Instapay, Vodafone Cash, Telda, or any
/// custom account the user adds), stored at:
/// users/{uid}/money_accounts/{accountId}
class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.name,
    required this.color,
    required this.balance,
  });

  final String id;
  final String name;
  final Color color;
  final double balance;

  factory MoneyAccount.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MoneyAccount(
      id: doc.id,
      name: data['name'] as String? ?? '',
      color: Color(data['colorValue'] as int? ?? Colors.grey.value),
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
    );
  }

  MoneyAccount copyWith({String? name, Color? color, double? balance}) {
    return MoneyAccount(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      balance: balance ?? this.balance,
    );
  }
}