import 'package:cloud_firestore/cloud_firestore.dart';

import '../../receipt/domain/receipt.dart';
import '../domain/expense.dart';

/// Firestore 구조 (여행·멤버는 TripRepository)
///   trips/{tripId}/expenses/{id}      title, category, currency, totalMinor,
///                                     paidAt, payerId(멤버 id), createdBy, receipt{...}
class ExpenseRepository {
  ExpenseRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection('trips');

  CollectionReference<Map<String, dynamic>> _expenses(String tripId) =>
      _trips.doc(tripId).collection('expenses');

  Stream<List<Expense>> watchExpenses(String tripId) => _expenses(tripId)
      .orderBy('paidAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Expense.fromMap(d.id, d.data())).toList());

  Future<void> saveReceipt({
    required String tripId,
    required String uid,
    required String payerId,
    required Receipt receipt,
    String? expenseId,
  }) {
    final data = <String, Object?>{
      'title': receipt.merchantName.isEmpty ? '이름 없는 지출' : receipt.merchantName,
      'category': receipt.category.name,
      'currency': receipt.currency.code,
      'totalMinor': receipt.totalMinor,
      'paidAt': (receipt.paidAt ?? DateTime.now()).toIso8601String(),
      'receipt': receipt.toMap(),
      'payerId': payerId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (expenseId != null) {
      return _expenses(tripId).doc(expenseId).update(data);
    }
    return _expenses(tripId).add({
      ...data,
      'createdBy': uid,
      'source': 'receipt',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteExpense(String tripId, String expenseId) =>
      _expenses(tripId).doc(expenseId).delete();
}
