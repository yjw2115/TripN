import '../../../core/money/currency.dart';
import '../../receipt/domain/receipt.dart';

/// 메뉴판의 메뉴 하나. 크기·온도별 가격이 다르면 각각 다른 메뉴로 둔다 ("카페라테 (아이스)").
class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.nameKo,
    required this.priceMinor,
    this.section = '',
    this.descriptionKo = '',
  });

  final String id;

  /// 메뉴판에 적힌 원래 이름.
  final String name;

  /// 한국어 이름.
  final String nameKo;

  /// 어떤 음식인지 한 줄 설명 (한국어). 없으면 빈 문자열.
  final String descriptionKo;

  /// 메뉴판의 구역 이름 (한국어, 예: 라멘, 음료).
  final String section;

  /// 가격 (최소 단위). 시가처럼 가격이 없으면 0.
  final int priceMinor;

  String get displayName => nameKo.isNotEmpty ? nameKo : name;

  MenuItem copyWith({String? name, String? nameKo, int? priceMinor}) => MenuItem(
        id: id,
        name: name ?? this.name,
        nameKo: nameKo ?? this.nameKo,
        priceMinor: priceMinor ?? this.priceMinor,
        section: section,
        descriptionKo: descriptionKo,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'nameKo': nameKo,
        'descriptionKo': descriptionKo,
        'section': section,
        'priceMinor': priceMinor,
      };

  factory MenuItem.fromMap(Map<String, Object?> map) => MenuItem(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        nameKo: map['nameKo'] as String? ?? '',
        descriptionKo: map['descriptionKo'] as String? ?? '',
        section: map['section'] as String? ?? '',
        priceMinor: (map['priceMinor'] as num?)?.toInt() ?? 0,
      );
}

/// 한 가게의 메뉴판. 여행 안에 저장해 두고 같은 가게에서 다시 주문할 때 쓴다.
class Menu {
  const Menu({
    required this.id,
    required this.storeName,
    required this.currency,
    required this.items,
    this.countryCode = '',
    this.taxIncluded = true,
    this.taxRatePercent = 0,
    this.serviceChargePercent = 0,
  });

  final String id;
  final String storeName;
  final Currency currency;

  /// ISO 3166-1 alpha-2. 모르면 빈 문자열.
  final String countryCode;
  final List<MenuItem> items;

  /// 메뉴판 가격에 세금이 들어 있으면 true (한국, 일본 税込, 유럽 대부분).
  final bool taxIncluded;

  /// 세금이 별도일 때 더할 세율 (예: 일본 税抜 10, 태국 VAT 7). 모르면 0.
  final double taxRatePercent;

  /// 가격에 더 붙는 봉사료 비율 (예: 태국 '++' 10).
  final double serviceChargePercent;

  /// 메뉴판에 나온 순서대로 구역을 묶는다.
  List<(String, List<MenuItem>)> get sections {
    final order = <String>[];
    final bySection = <String, List<MenuItem>>{};
    for (final item in items) {
      bySection.putIfAbsent(item.section, () {
        order.add(item.section);
        return [];
      }).add(item);
    }
    return [for (final s in order) (s, bySection[s]!)];
  }

  /// 인식한 메뉴판에 저장할 id를 붙인다.
  Menu copyWithId(String id) => Menu(
        id: id,
        storeName: storeName,
        currency: currency,
        countryCode: countryCode,
        items: items,
        taxIncluded: taxIncluded,
        taxRatePercent: taxRatePercent,
        serviceChargePercent: serviceChargePercent,
      );

  Menu copyWith({
    String? storeName,
    List<MenuItem>? items,
    bool? taxIncluded,
    double? taxRatePercent,
    double? serviceChargePercent,
  }) =>
      Menu(
        id: id,
        storeName: storeName ?? this.storeName,
        currency: currency,
        countryCode: countryCode,
        items: items ?? this.items,
        taxIncluded: taxIncluded ?? this.taxIncluded,
        taxRatePercent: taxRatePercent ?? this.taxRatePercent,
        serviceChargePercent: serviceChargePercent ?? this.serviceChargePercent,
      );

  Map<String, Object?> toMap() => {
        'storeName': storeName,
        'currency': currency.code,
        'countryCode': countryCode,
        'taxIncluded': taxIncluded,
        'taxRatePercent': taxRatePercent,
        'serviceChargePercent': serviceChargePercent,
        'items': [for (final i in items) i.toMap()],
      };

  factory Menu.fromMap(String id, Map<String, Object?> map) => Menu(
        id: id,
        storeName: map['storeName'] as String? ?? '',
        currency: Currency.of(map['currency'] as String? ?? 'KRW'),
        countryCode: map['countryCode'] as String? ?? '',
        taxIncluded: map['taxIncluded'] as bool? ?? true,
        taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 0,
        serviceChargePercent:
            (map['serviceChargePercent'] as num?)?.toDouble() ?? 0,
        items: [
          for (final e in (map['items'] as List?) ?? const [])
            MenuItem.fromMap(Map<String, Object?>.from(e as Map)),
        ],
      );
}

/// 미리 보는 영수증의 한 줄.
class OrderLine {
  const OrderLine({required this.item, required this.quantity});

  final MenuItem item;
  final int quantity;

  int get amountMinor => item.priceMinor * quantity;
}

/// 고른 메뉴로 계산한 미리 보는 영수증.
class OrderPreview {
  const OrderPreview({
    required this.menu,
    required this.lines,
    required this.subtotalMinor,
    required this.serviceChargeMinor,
    required this.taxMinor,
    required this.tipMinor,
  });

  final Menu menu;
  final List<OrderLine> lines;
  final int subtotalMinor;
  final int serviceChargeMinor;

  /// 세금이 별도일 때 더하는 금액. 가격에 들어 있으면 0.
  final int taxMinor;
  final int tipMinor;

  int get totalMinor => subtotalMinor + serviceChargeMinor + taxMinor + tipMinor;

  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  bool get isEmpty => lines.isEmpty;

  /// 메뉴판에 가게 이름이 없을 때 지출 이름: "중화소바 외 1개".
  String get _orderTitle => lines.isEmpty
      ? ''
      : '${lines.first.item.displayName}'
          '${lines.length > 1 ? ' 외 ${lines.length - 1}개' : ''}';

  /// 확정하면 영수증으로 바꿔서 영수증 확인 화면 → 지출로 저장한다 (영수증 없이 정산).
  Receipt toReceipt({DateTime? at}) => Receipt(
        merchantName: menu.storeName.isNotEmpty ? menu.storeName : _orderTitle,
        category: ExpenseCategory.food,
        paidAt: at ?? DateTime.now(),
        currency: menu.currency,
        countryCode: menu.countryCode,
        items: [
          for (final l in lines)
            ReceiptItem(
              id: 'm${l.item.id}',
              name: l.item.name,
              nameKo: l.item.nameKo,
              quantity: l.quantity.toDouble(),
              unitPriceMinor: l.item.priceMinor,
              amountMinor: l.amountMinor,
            ),
        ],
        taxMinor: taxMinor,
        taxIncluded: menu.taxIncluded,
        serviceChargeMinor: serviceChargeMinor,
        tipMinor: tipMinor,
        totalMinor: totalMinor,
        notes: '메뉴판 가격으로 계산',
      );
}

/// 고른 수량으로 미리 보는 영수증을 계산한다.
///
/// 봉사료는 소계에, 별도 세금은 소계 + 봉사료에 붙인다 (태국·싱가포르의 '++' 표기처럼
/// 봉사료에도 세금이 붙는 곳이 많다). 팁은 그대로 더한다.
OrderPreview previewOrder(Menu menu, Map<String, int> quantities,
    {int tipMinor = 0}) {
  final lines = [
    for (final item in menu.items)
      if ((quantities[item.id] ?? 0) > 0)
        OrderLine(item: item, quantity: quantities[item.id]!),
  ];
  final subtotal = lines.fold(0, (sum, l) => sum + l.amountMinor);
  final service = (subtotal * menu.serviceChargePercent / 100).round();
  final tax = menu.taxIncluded
      ? 0
      : ((subtotal + service) * menu.taxRatePercent / 100).round();
  return OrderPreview(
    menu: menu,
    lines: lines,
    subtotalMinor: subtotal,
    serviceChargeMinor: service,
    taxMinor: tax,
    tipMinor: tipMinor,
  );
}

/// 팁 문화가 있는 나라에서 보여줄 팁 비율 (소계 기준).
List<int> tipSuggestionsFor(String countryCode) => switch (countryCode) {
      'US' || 'CA' => const [15, 18, 20],
      _ => const [],
    };
