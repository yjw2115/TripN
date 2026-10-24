import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/menu/domain/menu.dart';
import 'package:travelen/features/menu/domain/menu_extraction.dart';
import 'package:travelen/features/receipt/domain/receipt_validator.dart';

Menu _menu({
  String currency = 'JPY',
  String country = 'JP',
  bool taxIncluded = true,
  double taxRate = 0,
  double service = 0,
  List<MenuItem>? items,
}) =>
    Menu(
      id: 'menu1',
      storeName: '이치란',
      currency: Currency.of(currency),
      countryCode: country,
      taxIncluded: taxIncluded,
      taxRatePercent: taxRate,
      serviceChargePercent: service,
      items: items ??
          const [
            MenuItem(id: 'a', name: 'ラーメン', nameKo: '라멘', priceMinor: 980, section: '라멘'),
            MenuItem(id: 'b', name: '替玉', nameKo: '면 추가', priceMinor: 210, section: '추가 옵션'),
            MenuItem(id: 'c', name: '生ビール', nameKo: '생맥주', priceMinor: 600, section: '음료'),
          ],
    );

void main() {
  group('previewOrder', () {
    test('tax-included prices add up as they are', () {
      final p = previewOrder(_menu(), {'a': 2, 'c': 1});
      expect([for (final l in p.lines) (l.item.nameKo, l.quantity, l.amountMinor)],
          [('라멘', 2, 1960), ('생맥주', 1, 600)]);
      expect((p.subtotalMinor, p.taxMinor, p.totalMinor, p.itemCount),
          (2560, 0, 2560, 3));
    });

    test('Japan 税抜 adds 10% tax', () {
      final p = previewOrder(_menu(taxIncluded: false, taxRate: 10), {'a': 1});
      expect((p.subtotalMinor, p.taxMinor, p.totalMinor), (980, 98, 1078));
    });

    test("Thailand '++' adds 10% service, then 7% VAT on both", () {
      final p = previewOrder(
          _menu(
            currency: 'THB',
            country: 'TH',
            taxIncluded: false,
            taxRate: 7,
            service: 10,
            items: const [
              MenuItem(id: 'p', name: 'Pad Thai', nameKo: '팟타이', priceMinor: 18000),
            ],
          ),
          {'p': 2});
      // ฿360 + 서비스 ฿36 + VAT 7% × ฿396 = ฿27.72 → ฿423.72
      expect((p.subtotalMinor, p.serviceChargeMinor, p.taxMinor, p.totalMinor),
          (36000, 3600, 2772, 42372));
    });

    test('a tip is added on top', () {
      final p = previewOrder(
          _menu(currency: 'USD', country: 'US', taxIncluded: false, taxRate: 8.875,
              items: const [MenuItem(id: 'b', name: 'Burger', nameKo: '버거', priceMinor: 1800)]),
          {'b': 1},
          tipMinor: 324);
      expect((p.taxMinor, p.tipMinor, p.totalMinor), (160, 324, 2284));
      expect(tipSuggestionsFor('US'), [15, 18, 20]);
      expect(tipSuggestionsFor('JP'), isEmpty);
    });

    test('nothing picked is an empty preview', () {
      expect(previewOrder(_menu(), {'a': 0}).isEmpty, isTrue);
    });
  });

  test('a confirmed order becomes a receipt that balances', () {
    final receipt = previewOrder(
            _menu(currency: 'THB', country: 'TH', taxIncluded: false, taxRate: 7, service: 10),
            {'a': 2, 'b': 1},
            tipMinor: 50)
        .toReceipt(at: DateTime(2026, 10, 24, 19));

    expect(receipt.merchantName, '이치란');
    expect(receipt.items.map((i) => (i.nameKo, i.quantity, i.amountMinor)),
        [('라멘', 2.0, 1960), ('면 추가', 1.0, 210)]);
    expect(checkReceipt(receipt).totalMatches, isTrue);
    expect(receipt.paidAt, DateTime(2026, 10, 24, 19));
  });

  test('without a store name the expense is named after the order', () {
    final menu = Menu.fromMap('m', {..._menu().toMap(), 'storeName': ''});
    expect(previewOrder(menu, {'a': 2, 'c': 1}).toReceipt().merchantName, '라멘 외 1개');
    expect(previewOrder(menu, {'b': 1}).toReceipt().merchantName, '면 추가');
  });

  test('menus group items by section in menu order', () {
    expect([for (final (name, items) in _menu().sections) (name, items.length)],
        [('라멘', 1), ('추가 옵션', 1), ('음료', 1)]);
  });

  test('menus survive a Firestore round trip', () {
    final menu = _menu(taxIncluded: false, taxRate: 10, service: 5);
    final back = Menu.fromMap('menu1', menu.toMap());
    expect((back.storeName, back.currency.code, back.taxIncluded, back.taxRatePercent,
            back.serviceChargePercent, back.items.length, back.items.first.nameKo),
        ('이치란', 'JPY', false, 10.0, 5.0, 3, '라멘'));
  });

  group('MenuExtraction', () {
    Map<String, Object?> json({
      String currency = 'JPY',
      String country = 'JP',
      String tax = 'unknown',
      num rate = 0,
      num service = 0,
    }) =>
        {
          'is_menu': true,
          'store_name': '一蘭 渋谷店',
          'country_code': country,
          'currency': currency,
          'tax': tax,
          'tax_rate_percent': rate,
          'service_charge_percent': service,
          'sections': [
            {
              'name': 'ラーメン',
              'name_ko': '라멘',
              'items': [
                {'name': 'ラーメン', 'name_ko': '라멘', 'description_ko': '돼지 뼈 육수 라멘', 'price': 980},
                {'name': '', 'name_ko': '', 'description_ko': '', 'price': 0},
              ],
            },
            {
              'name': 'Drinks',
              'name_ko': '음료',
              'items': [
                {'name': 'Latte (Iced)', 'name_ko': '카페라테 (아이스)', 'description_ko': '', 'price': 450.0},
              ],
            },
          ],
          'warnings': ['자릿세가 붙을 수 있어요', ' '],
        };

    test('flattens sections and converts prices', () {
      final e = MenuExtraction.fromModelJson(json());
      expect(e.menu.storeName, '一蘭 渋谷店');
      expect([for (final i in e.menu.items) (i.id, i.section, i.nameKo, i.priceMinor)],
          [('i0', '라멘', '라멘', 980), ('i1', '음료', '카페라테 (아이스)', 450)]);
      expect(e.menu.items.first.descriptionKo, '돼지 뼈 육수 라멘');
      expect(e.warnings, ['자릿세가 붙을 수 있어요']);
    });

    test('an unmarked menu follows the country: included in Japan, excluded in the US', () {
      final jp = MenuExtraction.fromModelJson(json()).menu;
      expect((jp.taxIncluded, jp.taxRatePercent), (true, 0.0));
      final us = MenuExtraction.fromModelJson(json(currency: 'USD', country: 'US')).menu;
      expect((us.taxIncluded, us.taxRatePercent), (false, 0.0));
    });

    test('"excluded" without a rate uses the standard rate where it is fixed', () {
      final jp = MenuExtraction.fromModelJson(json(tax: 'excluded')).menu;
      expect((jp.taxIncluded, jp.taxRatePercent), (false, 10.0));
      final th = MenuExtraction.fromModelJson(
              json(currency: 'THB', country: 'TH', tax: 'excluded', service: 10))
          .menu;
      expect((th.taxRatePercent, th.serviceChargePercent), (7.0, 10.0));
    });

    test('decimal currencies keep their cents', () {
      final usd = MenuExtraction.fromModelJson({
        ...json(currency: 'USD', country: 'US'),
        'sections': [
          {
            'name': '',
            'name_ko': '',
            'items': [
              {'name': 'Burger', 'name_ko': '버거', 'description_ko': '', 'price': 12.5},
            ],
          },
        ],
      }).menu;
      expect(usd.items.single.priceMinor, 1250);
      expect(usd.items.single.section, '');
    });
  });
}
