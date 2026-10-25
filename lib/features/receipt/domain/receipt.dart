import '../../../core/money/currency.dart';

/// 지출 분류. 가계부 통계와 아이콘에 쓴다.
enum ExpenseCategory {
  food('식비'),
  cafe('카페·간식'),
  shopping('쇼핑'),
  transport('교통'),
  lodging('숙소'),
  activity('관광·액티비티'),
  other('기타');

  const ExpenseCategory(this.label);
  final String label;

  static ExpenseCategory fromName(String? name) => ExpenseCategory.values
      .firstWhere((c) => c.name == name, orElse: () => ExpenseCategory.other);
}

/// 영수증의 품목 한 줄. 금액은 모두 최소 단위 정수다.
class ReceiptItem {
  const ReceiptItem({
    required this.id,
    required this.name,
    this.nameKo = '',
    this.quantity = 1,
    this.unitPriceMinor,
    required this.amountMinor,
    this.discountMinor = 0,
    this.participantIds = const [],
    this.takenBy = const {},
  });

  final String id;

  /// 영수증에 적힌 원래 이름.
  final String name;

  /// 한국어 번역. 원래 이름이 한국어면 비어 있을 수 있다.
  final String nameKo;
  final double quantity;
  final int? unitPriceMinor;

  /// 이 줄의 금액 (품목 할인 적용 전).
  final int amountMinor;

  /// 이 품목에만 적용된 할인 (양수).
  final int discountMinor;

  /// 이 품목을 함께 쓴 사람들. 비어 있으면 지출 참여자 전원으로 본다.
  /// 각자 가져간 개수([takenBy])가 있으면 남은 개수만 이 사람들끼리 나눈다.
  final List<String> participantIds;

  /// 한 번에 결제하고 각자 가져간 개수 (멤버 id → 개수). 그만큼은 그 사람 몫이다.
  final Map<String, int> takenBy;

  int get netMinor => amountMinor - discountMinor;

  /// 나눠 가질 수 있는 개수. 수량이 자연수가 아니면(무게 등) 한 덩어리로 본다.
  int get units => unitsOf(quantity);

  static int unitsOf(double quantity) =>
      quantity >= 1 && quantity == quantity.roundToDouble()
          ? quantity.toInt()
          : 1;

  int get takenCount => takenBy.values.fold(0, (sum, n) => sum + n);

  /// 아무도 가져가지 않아 함께 나누는 개수.
  int get sharedUnits => units > takenCount ? units - takenCount : 0;

  String get displayName => nameKo.isNotEmpty ? nameKo : name;

  /// 수량 × 단가가 금액과 맞지 않으면 true.
  bool get hasLineMismatch {
    final unit = unitPriceMinor;
    if (unit == null || unit == 0 || quantity <= 0) return false;
    return ((unit * quantity).round() - amountMinor).abs() > 1;
  }

  ReceiptItem copyWith({
    String? name,
    String? nameKo,
    double? quantity,
    int? unitPriceMinor,
    bool clearUnitPrice = false,
    int? amountMinor,
    int? discountMinor,
    List<String>? participantIds,
    Map<String, int>? takenBy,
  }) {
    return ReceiptItem(
      id: id,
      name: name ?? this.name,
      nameKo: nameKo ?? this.nameKo,
      quantity: quantity ?? this.quantity,
      unitPriceMinor:
          clearUnitPrice ? null : (unitPriceMinor ?? this.unitPriceMinor),
      amountMinor: amountMinor ?? this.amountMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      participantIds: participantIds ?? this.participantIds,
      takenBy: takenBy ?? this.takenBy,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'nameKo': nameKo,
        'quantity': quantity,
        'unitPriceMinor': unitPriceMinor,
        'amountMinor': amountMinor,
        'discountMinor': discountMinor,
        'participantIds': participantIds,
        'takenBy': takenBy,
      };

  factory ReceiptItem.fromMap(Map<String, Object?> map) => ReceiptItem(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        nameKo: map['nameKo'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unitPriceMinor: (map['unitPriceMinor'] as num?)?.toInt(),
        amountMinor: (map['amountMinor'] as num?)?.toInt() ?? 0,
        discountMinor: (map['discountMinor'] as num?)?.toInt() ?? 0,
        participantIds:
            (map['participantIds'] as List?)?.cast<String>() ?? const [],
        takenBy: {
          for (final e in ((map['takenBy'] as Map?) ?? const {}).entries)
            if (e.value is num && (e.value as num) > 0)
              e.key as String: (e.value as num).toInt(),
        },
      );
}

/// 인식(또는 사용자가 수정)한 영수증 한 장.
class Receipt {
  const Receipt({
    required this.merchantName,
    this.category = ExpenseCategory.other,
    this.paidAt,
    required this.currency,
    this.countryCode = '',
    required this.items,
    this.taxMinor = 0,
    this.taxIncluded = true,
    this.serviceChargeMinor = 0,
    this.tipMinor = 0,
    this.discountMinor = 0,
    required this.totalMinor,
    this.notes = '',
  });

  final String merchantName;
  final ExpenseCategory category;
  final DateTime? paidAt;
  final Currency currency;

  /// ISO 3166-1 alpha-2. 모르면 빈 문자열.
  final String countryCode;
  final List<ReceiptItem> items;

  /// 세금. [taxIncluded]가 true면 품목 가격에 이미 들어 있는 금액(참고용)이다.
  final int taxMinor;
  final bool taxIncluded;
  final int serviceChargeMinor;
  final int tipMinor;

  /// 영수증 전체에 적용된 할인 (양수).
  final int discountMinor;

  /// 실제로 낸 총액.
  final int totalMinor;
  final String notes;

  int get itemsNetMinor => items.fold(0, (sum, i) => sum + i.netMinor);

  /// 품목과 부가 금액으로 계산한 총액.
  int get computedTotalMinor =>
      itemsNetMinor +
      (taxIncluded ? 0 : taxMinor) +
      serviceChargeMinor +
      tipMinor -
      discountMinor;

  Receipt copyWith({
    String? merchantName,
    ExpenseCategory? category,
    DateTime? paidAt,
    Currency? currency,
    String? countryCode,
    List<ReceiptItem>? items,
    int? taxMinor,
    bool? taxIncluded,
    int? serviceChargeMinor,
    int? tipMinor,
    int? discountMinor,
    int? totalMinor,
    String? notes,
  }) {
    return Receipt(
      merchantName: merchantName ?? this.merchantName,
      category: category ?? this.category,
      paidAt: paidAt ?? this.paidAt,
      currency: currency ?? this.currency,
      countryCode: countryCode ?? this.countryCode,
      items: items ?? this.items,
      taxMinor: taxMinor ?? this.taxMinor,
      taxIncluded: taxIncluded ?? this.taxIncluded,
      serviceChargeMinor: serviceChargeMinor ?? this.serviceChargeMinor,
      tipMinor: tipMinor ?? this.tipMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      totalMinor: totalMinor ?? this.totalMinor,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toMap() => {
        'merchantName': merchantName,
        'category': category.name,
        'paidAt': paidAt?.toIso8601String(),
        'currency': currency.code,
        'countryCode': countryCode,
        'items': items.map((i) => i.toMap()).toList(),
        'taxMinor': taxMinor,
        'taxIncluded': taxIncluded,
        'serviceChargeMinor': serviceChargeMinor,
        'tipMinor': tipMinor,
        'discountMinor': discountMinor,
        'totalMinor': totalMinor,
        'notes': notes,
      };

  factory Receipt.fromMap(Map<String, Object?> map) => Receipt(
        merchantName: map['merchantName'] as String? ?? '',
        category: ExpenseCategory.fromName(map['category'] as String?),
        paidAt: DateTime.tryParse(map['paidAt'] as String? ?? ''),
        currency: Currency.of(map['currency'] as String? ?? 'KRW'),
        countryCode: map['countryCode'] as String? ?? '',
        items: ((map['items'] as List?) ?? const [])
            .map((e) => ReceiptItem.fromMap(Map<String, Object?>.from(e as Map)))
            .toList(),
        taxMinor: (map['taxMinor'] as num?)?.toInt() ?? 0,
        taxIncluded: map['taxIncluded'] as bool? ?? true,
        serviceChargeMinor: (map['serviceChargeMinor'] as num?)?.toInt() ?? 0,
        tipMinor: (map['tipMinor'] as num?)?.toInt() ?? 0,
        discountMinor: (map['discountMinor'] as num?)?.toInt() ?? 0,
        totalMinor: (map['totalMinor'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String? ?? '',
      );
}
