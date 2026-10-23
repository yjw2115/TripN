import '../../../core/money/currency.dart';
import '../../receipt/domain/receipt.dart';

/// 여행(모임). 1단계에서는 사용자마다 기본 여행 하나를 자동으로 만든다.
class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
  });

  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;

  factory Trip.fromMap(String id, Map<String, Object?> map) => Trip(
        id: id,
        name: map['name'] as String? ?? '',
        ownerId: map['ownerId'] as String? ?? '',
        memberIds: (map['memberIds'] as List?)?.cast<String>() ?? const [],
      );
}

/// 여행 중 지출 한 건. 영수증으로 만들었으면 [receipt]에 품목이 들어 있다.
class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.currency,
    required this.totalMinor,
    required this.paidAt,
    required this.payerId,
    required this.createdBy,
    this.receipt,
  });

  final String id;
  final String title;
  final ExpenseCategory category;
  final Currency currency;
  final int totalMinor;
  final DateTime paidAt;
  final String payerId;
  final String createdBy;
  final Receipt? receipt;

  factory Expense.fromMap(String id, Map<String, Object?> map) {
    final receiptMap = map['receipt'] as Map?;
    return Expense(
      id: id,
      title: map['title'] as String? ?? '',
      category: ExpenseCategory.fromName(map['category'] as String?),
      currency: Currency.of(map['currency'] as String? ?? 'KRW'),
      totalMinor: (map['totalMinor'] as num?)?.toInt() ?? 0,
      paidAt: DateTime.tryParse(map['paidAt'] as String? ?? '') ?? DateTime(2000),
      payerId: map['payerId'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
      receipt: receiptMap == null
          ? null
          : Receipt.fromMap(Map<String, Object?>.from(receiptMap)),
    );
  }
}
