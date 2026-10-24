import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/money/exchange_rate.dart';
import '../../receipt/domain/receipt.dart';
import '../domain/expense.dart';

/// Firestore 구조 (여행·멤버는 TripRepository)
///   trips/{tripId}/expenses/{id}      title, category, currency, totalMinor,
///                                     paidAt, payerId(멤버 id), participantIds(함께 쓴 멤버 id),
///                                     createdBy, receipt{...},
///                                     krwRate, rateSource, rateDate (지출할 때 고정한 환율)
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
    required List<String> participantIds,
    required Receipt receipt,
    String? expenseId,
    FixedRate? rate,

    /// 고칠 때 통화·날짜가 그대로면 처음 고정한 환율을 건드리지 않는다.
    bool keepRate = false,
  }) {
    final data = <String, Object?>{
      'title': receipt.merchantName.isEmpty ? '이름 없는 지출' : receipt.merchantName,
      'category': receipt.category.name,
      'currency': receipt.currency.code,
      'totalMinor': receipt.totalMinor,
      'paidAt': (receipt.paidAt ?? DateTime.now()).toIso8601String(),
      'receipt': receipt.toMap(),
      'payerId': payerId,
      'participantIds': participantIds,
      ...?rate?.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (expenseId != null) {
      return _expenses(tripId).doc(expenseId).update({
        ...data,
        // 환율을 새로 못 정했으면 예전 환율이 잘못 남지 않게 지우고, 나중에 채운다 (fillRate).
        if (!keepRate && rate == null) ...{
          'krwRate': FieldValue.delete(),
          'rateSource': FieldValue.delete(),
          'rateDate': FieldValue.delete(),
        },
      });
    }
    return _expenses(tripId).add({
      ...data,
      'createdBy': uid,
      'source': 'receipt',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 저장할 때 환율을 못 받았던(오프라인 등) 지출이나 예전 지출에 환율을 채운다.
  Future<void> fillRate(String tripId, String expenseId, FixedRate rate) =>
      _expenses(tripId).doc(expenseId).update(rate.toMap());

  /// 멤버를 지울 때 그 사람이 함께 쓴 사람으로만 들어 있는 지출에서 뺀다.
  Future<void> removeParticipant(
      String tripId, String memberId, Iterable<String> expenseIds) {
    final batch = _db.batch();
    for (final id in expenseIds) {
      batch.update(_expenses(tripId).doc(id), {
        'participantIds': FieldValue.arrayRemove([memberId]),
      });
    }
    return batch.commit();
  }

  Future<void> deleteExpense(String tripId, String expenseId) =>
      _expenses(tripId).doc(expenseId).delete();
}
