import '../../../core/money/currency.dart';
import 'receipt.dart';

/// 영수증 인식 결과. 인식기(Gemini, 나중에 온디바이스 OCR 등)와 상관없이 같은 형태다.
class ReceiptExtraction {
  const ReceiptExtraction({
    required this.isReceipt,
    required this.receiptCount,
    required this.receipt,
    required this.warnings,
  });

  /// 사진이 영수증이 아니면 false.
  final bool isReceipt;

  /// 사진에 서로 다른 영수증이 몇 장 찍혔는지. 2 이상이면 다시 찍도록 안내한다.
  final int receiptCount;
  final Receipt receipt;

  /// 사용자에게 보여줄 참고 사항 (한국어).
  final List<String> warnings;

  /// LLM이 돌려준 JSON(스키마: `receiptJsonSchema`)을 앱 모델로 바꾼다.
  factory ReceiptExtraction.fromModelJson(Map<String, Object?> json) {
    final currency = Currency.of(_str(json['currency'], fallback: 'KRW'));
    int minor(Object? v) => currency.toMinor(_num(v).abs());

    final rawItems = (json['items'] as List?) ?? const [];
    final items = <ReceiptItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      final m = Map<String, Object?>.from(rawItems[i] as Map);
      final unitPrice = _num(m['unit_price']);
      final quantity = _num(m['quantity']);
      // 일부 영수증은 품목 줄 자체에 음수 금액으로 할인을 찍는다.
      final amount = _num(m['amount']);
      final isNegativeLine = amount < 0;
      items.add(ReceiptItem(
        id: 'i$i',
        name: _str(m['name']),
        nameKo: _str(m['name_ko']),
        quantity: quantity > 0 ? quantity.toDouble() : 1,
        unitPriceMinor: unitPrice > 0 ? currency.toMinor(unitPrice) : null,
        amountMinor: isNegativeLine ? 0 : currency.toMinor(amount),
        discountMinor: isNegativeLine
            ? currency.toMinor(-amount) + minor(m['discount'])
            : minor(m['discount']),
      ));
    }

    final receipt = Receipt(
      merchantName: _str(json['merchant_name']),
      category: ExpenseCategory.fromName(_str(json['category'])),
      paidAt: _parseDateTime(_str(json['date']), _str(json['time'])),
      currency: currency,
      countryCode: _str(json['country_code']).toUpperCase(),
      items: items,
      taxMinor: minor(json['tax']),
      taxIncluded: json['tax_included'] as bool? ?? true,
      serviceChargeMinor: minor(json['service_charge']),
      tipMinor: minor(json['tip']),
      discountMinor: minor(json['discount']),
      totalMinor: minor(json['total']),
    );

    return ReceiptExtraction(
      isReceipt: json['is_receipt'] as bool? ?? true,
      receiptCount: _num(json['receipt_count']).toInt().clamp(0, 99),
      warnings: ((json['warnings'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      receipt: _dropDoubleCountedDiscount(receipt),
    );
  }
}

/// 모델이 품목 할인을 넣고 "할인 합계" 줄(优惠总计 등)을 전체 할인에 또 넣는 경우가 있다.
/// 전체 할인이 품목 할인 합계와 같고, 그걸 빼야 총액이 맞을 때만 전체 할인을 없앤다.
Receipt _dropDoubleCountedDiscount(Receipt r) {
  final itemDiscounts = r.items.fold(0, (sum, i) => sum + i.discountMinor);
  if (r.discountMinor == 0 || itemDiscounts == 0) return r;
  if ((r.discountMinor - itemDiscounts).abs() > 1) return r;
  final withoutDiscount = r.copyWith(discountMinor: 0);
  final tolerance = r.items.length + 1;
  final balancesWith = (r.totalMinor - r.computedTotalMinor).abs() <= tolerance;
  final balancesWithout =
      (r.totalMinor - withoutDiscount.computedTotalMinor).abs() <= tolerance;
  return !balancesWith && balancesWithout ? withoutDiscount : r;
}

String _str(Object? v, {String fallback = ''}) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

num _num(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.replaceAll(',', '')) ?? 0;
  return 0;
}

DateTime? _parseDateTime(String date, String time) {
  final d = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(date);
  if (d == null) return null;
  final t = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time);
  final year = int.parse(d[1]!);
  final month = int.parse(d[2]!);
  final day = int.parse(d[3]!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(
    year,
    month,
    day,
    t == null ? 0 : int.parse(t[1]!).clamp(0, 23),
    t == null ? 0 : int.parse(t[2]!).clamp(0, 59),
  );
}
