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
    this.participantIds = const [],
    this.source = 'receipt',
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

  /// 이 지출을 함께 쓴 멤버 id. 저장할 때 정한다. 비어 있으면(예전 지출) 여행 멤버 전원.
  final List<String> participantIds;

  /// 'receipt'(영수증을 찍어서) 또는 'menu'(메뉴판에서 골라서).
  final String source;
  final FixedRate? _rate;

  /// 지출할 때 고정한 원화 환율. 아직 못 정했으면 null (원화 지출은 언제나 1).
  FixedRate? get rate =>
      _rate ?? (currency == Currency.krw ? FixedRate.krw : null);

  int? get totalKrw => rate?.toKrw(totalMinor, currency);

  /// 이 멤버가 결제자이거나 품목 참여자로 콕 집혀 있으면 true. 그런 멤버는 지울 수 없다.
  /// 함께 쓴 사람([participantIds])에만 있으면 지울 때 거기서 빼면 된다.
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
      participantIds:
          (map['participantIds'] as List?)?.cast<String>() ?? const [],
      source: map['source'] as String? ?? 'receipt',
      rate: FixedRate.fromMap(map),
    );
  }
}
