import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/money_account.dart';
import '../models/money_transaction.dart';

/// Handles all Firestore reads/writes for the Money feature.
///
/// Data lives per signed-in user:
///   users/{uid}/money_accounts/{accountId}
///   users/{uid}/money_accounts/{accountId}/transactions/{transactionId}
///
/// An account's `balance` field is always kept authoritative and is updated
/// atomically (via Firestore transactions) whenever a money transaction is
/// added, edited, or deleted, so it never drifts out of sync.
class MoneyService {
  MoneyService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('MoneyService used with no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _accounts =>
      _db.collection('users').doc(_uid).collection('money_accounts');

  CollectionReference<Map<String, dynamic>> _transactions(String accountId) =>
      _accounts.doc(accountId).collection('transactions');

  /// The four accounts every user starts out with.
  static const List<(String, Color)> defaultAccounts = [
    ('Cash', Colors.green),
    ('Instapay', Colors.purple),
    ('Vodafone Cash', Colors.red),
    ('Telda', Colors.black),
  ];

  /// Creates the default accounts the first time a user has none.
  /// Safe to call every time the Money screen opens.
  Future<void> ensureDefaultAccounts() async {
    final existing = await _accounts.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final batch = _db.batch();
    for (final (name, color) in defaultAccounts) {
      final ref = _accounts.doc();
      batch.set(ref, {
        'name': name,
        'colorValue': color.value,
        'balance': 0.0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Stream<List<MoneyAccount>> streamAccounts() {
    return _accounts.orderBy('createdAt').snapshots().map(
          (snap) => snap.docs.map(MoneyAccount.fromDoc).toList(),
        );
  }

  Stream<MoneyAccount> streamAccount(String accountId) {
    return _accounts.doc(accountId).snapshots().map(MoneyAccount.fromDoc);
  }

  Stream<List<MoneyTransaction>> streamTransactions(String accountId) {
    return _transactions(accountId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(MoneyTransaction.fromDoc).toList());
  }

  Future<void> addAccount({
    required String name,
    required Color color,
    required double initialBalance,
  }) {
    return _accounts.add({
      'name': name,
      'colorValue': color.value,
      'balance': initialBalance,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAccount({
    required String accountId,
    required String name,
    required Color color,
  }) {
    return _accounts.doc(accountId).update({
      'name': name,
      'colorValue': color.value,
    });
  }

  /// Deletes an account and all of its transactions.
  Future<void> deleteAccount(String accountId) async {
    final txSnap = await _transactions(accountId).get();
    final batch = _db.batch();
    for (final doc in txSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_accounts.doc(accountId));
    await batch.commit();
  }

  /// Adds a transaction and atomically adjusts the account balance.
  Future<void> addTransaction({
    required String accountId,
    required double amount,
    required String note,
    required DateTime date,
  }) {
    final accountRef = _accounts.doc(accountId);
    final txRef = _transactions(accountId).doc();
    return _db.runTransaction((t) async {
      final snap = await t.get(accountRef);
      final current = (snap.data()?['balance'] as num?)?.toDouble() ?? 0;
      t.set(txRef, {
        'amount': amount,
        'note': note,
        'date': Timestamp.fromDate(date),
        'createdAt': FieldValue.serverTimestamp(),
      });
      t.update(accountRef, {'balance': current + amount});
    });
  }

  /// Edits a transaction, backing out its old amount and applying the new
  /// one so the account balance stays correct.
  Future<void> editTransaction({
    required String accountId,
    required String transactionId,
    required double oldAmount,
    required double newAmount,
    required String note,
    required DateTime date,
  }) {
    final accountRef = _accounts.doc(accountId);
    final txRef = _transactions(accountId).doc(transactionId);
    return _db.runTransaction((t) async {
      final snap = await t.get(accountRef);
      final current = (snap.data()?['balance'] as num?)?.toDouble() ?? 0;
      t.update(txRef, {
        'amount': newAmount,
        'note': note,
        'date': Timestamp.fromDate(date),
      });
      t.update(accountRef, {'balance': current - oldAmount + newAmount});
    });
  }

  Future<void> deleteTransaction({
    required String accountId,
    required String transactionId,
    required double amount,
  }) {
    final accountRef = _accounts.doc(accountId);
    final txRef = _transactions(accountId).doc(transactionId);
    return _db.runTransaction((t) async {
      final snap = await t.get(accountRef);
      final current = (snap.data()?['balance'] as num?)?.toDouble() ?? 0;
      t.delete(txRef);
      t.update(accountRef, {'balance': current - amount});
    });
  }
}