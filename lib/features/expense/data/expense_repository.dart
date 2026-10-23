import 'package:cloud_firestore/cloud_firestore.dart';

import '../../receipt/domain/receipt.dart';
import '../domain/expense.dart';

/// Firestore 구조
///   trips/{tripId}                    name, ownerId, memberIds, createdAt
///   trips/{tripId}/expenses/{id}      title, category, currency, totalMinor,
///                                     paidAt, payerId, createdBy, receipt{...}
class ExpenseRepository {
  ExpenseRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection('trips');

  CollectionReference<Map<String, dynamic>> _expenses(String tripId) =>
      _trips.doc(tripId).collection('expenses');

  /// 사용자의 여행을 하나 가져오고, 없으면 기본 여행을 만든다.
  Future<Trip> ensureDefaultTrip(String uid) async {
    final existing =
        await _trips.where('memberIds', arrayContains: uid).limit(1).get();
    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;
      return Trip.fromMap(doc.id, doc.data());
    }
    final ref = _trips.doc();
    await ref.set({
      'name': '내 여행',
      'ownerId': uid,
      'memberIds': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Trip(id: ref.id, name: '내 여행', ownerId: uid, memberIds: [uid]);
  }

  Stream<List<Expense>> watchExpenses(String tripId) => _expenses(tripId)
      .orderBy('paidAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Expense.fromMap(d.id, d.data())).toList());

  Future<void> saveReceipt({
    required String tripId,
    required String uid,
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
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (expenseId != null) {
      return _expenses(tripId).doc(expenseId).update(data);
    }
    return _expenses(tripId).add({
      ...data,
      'payerId': uid,
      'createdBy': uid,
      'source': 'receipt',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteExpense(String tripId, String expenseId) =>
      _expenses(tripId).doc(expenseId).delete();
}
