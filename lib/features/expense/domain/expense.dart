import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';
import '../../receipt/domain/receipt.dart';

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
    FixedRate? rate,
  }) : _rate = rate;

  final String id;
  final String title;
  final ExpenseCategory category;
  final Currency currency;
  final int totalMinor;
  final DateTime paidAt;

  /// 낸 사람의 멤버 id (`trips/{tripId}/members/{id}`).
  final String payerId;
  final String createdBy;
  final Receipt? receipt;
  final FixedRate? _rate;

  /// 지출할 때 고정한 원화 환율. 아직 못 정했으면 null (원화 지출은 언제나 1).
  FixedRate? get rate =>
      _rate ?? (currency == Currency.krw ? FixedRate.krw : null);

  int? get totalKrw => rate?.toKrw(totalMinor, currency);

  /// 이 멤버가 결제자이거나 품목 참여자면 true. 멤버를 지워도 되는지 볼 때 쓴다.
  bool involves(String memberId) =>
      payerId == memberId ||
      (receipt?.items.any((i) => i.participantIds.contains(memberId)) ??
          false);

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
      rate: FixedRate.fromMap(map),
    );
  }
}
