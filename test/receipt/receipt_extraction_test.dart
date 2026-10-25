import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/money_format.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/receipt/domain/receipt_extraction.dart';
import 'package:travelen/features/receipt/domain/receipt_validator.dart';

Map<String, Object?> modelJson({
  required String currency,
  required List<Map<String, Object?>> items,
  required num total,
  num tax = 0,
  bool taxIncluded = true,
  num serviceCharge = 0,
  num tip = 0,
  num discount = 0,
  String date = '',
  String time = '',
}) =>
    {
      'is_receipt': true,
      'receipt_count': 1,
      'merchant_name': 'Shop',
      'category': 'food',
      'country_code': 'jp',
      'currency': currency,
      'date': date,
      'time': time,
      'items': items,
      'subtotal': 0,
      'tax': tax,
      'tax_included': taxIncluded,
      'service_charge': serviceCharge,
      'tip': tip,
      'discount': discount,
      'total': total,
      'warnings': ['', '보증금이 포함돼 있어요'],
    };

Map<String, Object?> item(
  String name,
  num amount, {
  num quantity = 1,
  num unitPrice = 0,
  num discount = 0,
}) =>
    {
      'name': name,
      'name_ko': '',
      'quantity': quantity,
      'unit_price': unitPrice,
      'amount': amount,
      'discount': discount,
    };

void main() {
  group('Currency', () {
    test('converts major amounts to minor units without float drift', () {
      expect(Currency.of('USD').toMinor(0.29), 29);
      expect(Currency.of('usd').toMinor(249.32), 24932);
      expect(Currency.of('JPY').toMinor(16126), 16126);
      expect(Currency.of('VND').toMinor(1030000), 1030000);
      expect(Currency.of('KWD').decimals, 2, reason: '목록에 없으면 2자리');
    });

    test('formats money per currency', () {
      expect(formatMoney(1250, Currency.of('USD')), r'$12.50');
      expect(formatMoney(16126, Currency.of('JPY')), '¥16,126');
      expect(formatMoney(12500, Currency.krw), '12,500원');
      expect(formatMoneyPlain(1185, Currency.of('EUR')), '11.85');
      expect(parseMoneyInput('1,234.5', Currency.of('USD')), 123450);
      expect(parseMoneyInput('abc', Currency.of('USD')), isNull);
    });

    test('reads typed amounts the way they are printed on the receipt', () {
      final vnd = Currency.of('VND');
      final usd = Currency.of('USD');
      final eur = Currency.of('EUR');
      // 소수점이 없는 통화: 점과 쉼표는 천 단위
      expect(parseMoneyInput('130.000', vnd), 130000);
      expect(parseMoneyInput('130,000', vnd), 130000);
      expect(parseMoneyInput('1.283.500', vnd), 1283500);
      expect(parseMoneyInput('12.500', Currency.krw), 12500);
      expect(parseMoneyInput('3,010', Currency.of('JPY')), 3010);
      // 소수 2자리 통화: 마지막 구분 기호 뒤가 1~2자리면 소수점
      expect(parseMoneyInput('52.77', usd), 5277);
      expect(parseMoneyInput('52,77', usd), 5277);
      expect(parseMoneyInput('52.7', usd), 5270);
      expect(parseMoneyInput('1,234', usd), 123400);
      expect(parseMoneyInput('1,234.56', usd), 123456);
      expect(parseMoneyInput('1.234,56', eur), 123456);
      expect(parseMoneyInput('11,85', eur), 1185);
      expect(parseMoneyInput('12.', usd), 1200);
      expect(parseMoneyInput('.5', usd), 50);
      expect(parseMoneyInput(' 4 300 ', Currency.krw), 4300);
      // 숫자가 없거나 다른 기호가 섞이면 읽지 않는다
      expect(parseMoneyInput('', usd), isNull);
      expect(parseMoneyInput('.', usd), isNull);
      expect(parseMoneyInput('1-2', usd), isNull);
    });
  });

  group('ReceiptExtraction.fromModelJson', () {
    test('Japan: tax already included in prices', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'JPY',
        items: [
          item('焼肉14種C', 15356, quantity: 2, unitPrice: 7678),
          item('チャージ料', 770, quantity: 2, unitPrice: 385),
        ],
        tax: 1466,
        total: 16126,
        date: '2025-01-07',
        time: '22:14',
      ));
      expect(r.receipt.currency.code, 'JPY');
      expect(r.receipt.countryCode, 'JP');
      expect(r.receipt.paidAt, DateTime(2025, 1, 7, 22, 14));
      expect(r.receipt.items.first.unitPriceMinor, 7678);
      expect(r.warnings, ['보증금이 포함돼 있어요']);
      expect(checkReceipt(r.receipt).isClean, isTrue);
    });

    test('US: sales tax added on top', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'USD',
        items: [
          item('Taco Dinner Combo', 17),
          item('TACO de Camaron', 4.5),
          item('Imported Beer', 7),
        ],
        tax: 2.22,
        taxIncluded: false,
        total: 30.72,
      ));
      expect(r.receipt.computedTotalMinor, 3072);
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('China: per-item barcode discounts', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'CNY',
        items: [
          item('大白菜', 7.0),
          item('白萝卜', 2.9, discount: 1.2),
          item('冬瓜切片', 4.2, discount: 1.7),
          item('冬瓜切片', 4.7, discount: 1.9),
          item('菜心(包)', 5.5, discount: 2.2),
          item('客家佬豆腐花280g', 2.9),
        ],
        total: 20.2,
      ));
      expect(r.receipt.items[1].netMinor, 170);
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('a discount-summary line is not counted twice', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'CNY',
        items: [
          item('白萝卜', 2.9, discount: 1.2),
          item('冬瓜切片', 4.2, discount: 1.7),
          item('客家佬豆腐花280g', 2.9),
        ],
        discount: 2.9, // 优惠总计 = 1.2 + 1.7
        total: 7.1,
      ));
      expect(r.receipt.discountMinor, 0);
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('keeps a real receipt-wide discount that happens to equal item discounts',
        () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'CNY',
        items: [item('A', 10, discount: 1), item('B', 10)],
        discount: 1,
        total: 18,
      ));
      expect(r.receipt.discountMinor, 100);
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('negative discount lines are folded into the line discount', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'CNY',
        items: [item('黄金三脆多汁鸡堡', 19.9), item('优惠', -9.9)],
        total: 10,
      ));
      expect(r.receipt.items[1].amountMinor, 0);
      expect(r.receipt.items[1].discountMinor, 990);
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('Philippines: senior-citizen deductions as a receipt-level discount',
        () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'PHP',
        items: [item('(S)SSG EGG Mu', 105), item('(S)sm PRC 12o', 15)],
        discount: 34.29,
        total: 85.71,
      ));
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('Vietnam: large zero-decimal amounts with service charge', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'VND',
        items: [item('Vn Coffee', 90000, quantity: 2, unitPrice: 45000)],
        serviceCharge: 4500,
        total: 94500,
      ));
      expect(r.receipt.totalMinor, 94500);
      expect(checkReceipt(r.receipt).totalMatches, isTrue);
    });

    test('Korea: 부가세 is included in the item prices', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'KRW',
        items: [
          item('페퍼로니 앤 칩스', 29000, unitPrice: 29000),
          item('토마토 파스타', 14000, unitPrice: 14000),
          item('수제 돈가스', 13000, unitPrice: 13000),
          item('새우 실치 필라', 14000, unitPrice: 14000),
          item('콜라', 6000, quantity: 3, unitPrice: 2000),
        ],
        tax: 6906,
        total: 76000,
        date: '2025-10-04',
        time: '12:33',
      ));
      expect(r.receipt.currency, Currency.krw);
      expect(r.receipt.taxMinor, 6906);
      final check = checkReceipt(r.receipt);
      expect(check.isClean, isTrue);
      expect(check.isTotalOnly, isFalse);
    });

    test('Korea: a card sales slip with only a total', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'KRW',
        items: const [],
        total: 45000,
      ));
      final check = checkReceipt(r.receipt);
      expect(check.isTotalOnly, isTrue);
      expect(check.totalMatches, isFalse);
    });

    test('tolerates missing or odd fields', () {
      final r = ReceiptExtraction.fromModelJson({
        'currency': '',
        'items': [
          {'name': 'Water', 'amount': '1,200', 'quantity': 0},
        ],
        'total': 1200,
        'date': '2019-13-40',
      });
      expect(r.isReceipt, isTrue);
      expect(r.receipt.currency, Currency.krw);
      expect(r.receipt.items.single.quantity, 1);
      expect(r.receipt.items.single.amountMinor, 1200);
      expect(r.receipt.paidAt, isNull);
      expect(r.receipt.category, ExpenseCategory.other);
    });
  });

  group('checkReceipt', () {
    test('reports how much the items are short of the total', () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'THB',
        items: [item('ข้าวเหนียว', 138, quantity: 6, unitPrice: 23)],
        total: 1362,
      ));
      final check = checkReceipt(r.receipt);
      expect(check.totalMatches, isFalse);
      expect(check.differenceMinor, 122400);
    });

    test('flags lines where quantity x unit price disagrees with the amount',
        () {
      final r = ReceiptExtraction.fromModelJson(modelJson(
        currency: 'THB',
        items: [item('จอผักกาด', 164, quantity: 2, unitPrice: 73)],
        total: 164,
      ));
      final check = checkReceipt(r.receipt);
      expect(check.totalMatches, isTrue);
      expect(check.mismatchedItemIds, {'i0'});
    });
  });

  test('Receipt survives a Firestore-style map round trip', () {
    final original = ReceiptExtraction.fromModelJson(modelJson(
      currency: 'EUR',
      items: [item('ACQUA', 1.32, quantity: 6, unitPrice: 0.22)],
      tax: 0.12,
      total: 1.32,
      date: '2024-02-06',
    )).receipt;
    final restored = Receipt.fromMap(original.toMap());
    expect(restored.toMap(), original.toMap());
  });

  test('what each took survives the round trip', () {
    const item = ReceiptItem(
        id: 'i1',
        name: 'キットカット',
        quantity: 5,
        amountMinor: 1000,
        takenBy: {'j': 3, 'm': 2});
    final restored = ReceiptItem.fromMap(item.toMap());
    expect(restored.takenBy, {'j': 3, 'm': 2});
    expect(restored.sharedUnits, 0);
    // 예전 품목에는 없다.
    expect(ReceiptItem.fromMap({'id': 'old', 'amountMinor': 100}).takenBy,
        isEmpty);
  });
}
