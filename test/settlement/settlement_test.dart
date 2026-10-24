import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/settlement/domain/settlement.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(id: 'j', name: '지민', uid: 'u1');
const _minsu = Member(id: 'm', name: '민수');
const _seoyeon = Member(id: 's', name: '서연');
const _members = [_jimin, _minsu, _seoyeon];
const _ids = ['j', 'm', 's'];

const _jpyRate = FixedRate(krwPerUnit: 9.0, source: RateSource.koreaexim);

Expense _expense({
  required String payer,
  required int total,
  Currency currency = Currency.krw,
  FixedRate? rate,
  List<String> together = const [],
  List<ReceiptItem> items = const [],
}) =>
    Expense(
      id: 'e${total}_$payer',
      title: '지출',
      category: ExpenseCategory.food,
      currency: currency,
      totalMinor: total,
      paidAt: DateTime(2026, 10, 23),
      payerId: payer,
      createdBy: 'u1',
      participantIds: together,
      rate: rate,
      receipt: items.isEmpty
          ? null
          : Receipt(
              merchantName: '가게',
              currency: currency,
              items: items,
              totalMinor: total),
    );

ReceiptItem _item(String id, int amount, [List<String> who = const []]) =>
    ReceiptItem(id: id, name: id, amountMinor: amount, participantIds: who);

void main() {
  group('allocate', () {
    test('always adds up to the total', () {
      final split = allocate(10000, {'j': 1, 'm': 1, 's': 1});
      expect(split.values.reduce((a, b) => a + b), 10000);
      expect(split, {'j': 3334, 'm': 3333, 's': 3333});
    });

    test('the payer takes the leftover won on an even split', () {
      expect(allocate(10000, {'j': 1, 'm': 1, 's': 1}, priority: ['s']),
          {'j': 3333, 'm': 3333, 's': 3334});
    });

    test('leftovers go to the largest dropped fraction first', () {
      // 100 × 2/3 = 66.67, 100 × 1/3 = 33.33
      expect(allocate(100, {'j': 2, 'm': 1}, priority: ['m']),
          {'j': 67, 'm': 33});
    });

    test('negative amounts (discount lines) split the same way', () {
      expect(allocate(-100, {'j': 1, 'm': 1, 's': 1}, priority: ['j']),
          {'j': -34, 'm': -33, 's': -33});
    });

    test('all-zero weights fall back to an even split', () {
      expect(allocate(10, {'j': 0, 'm': 0}), {'j': 5, 'm': 5});
    });
  });

  group('sharesOf', () {
    test('a total-only receipt splits evenly among those who shared it', () {
      final e = _expense(payer: 'j', total: 30000, together: ['j', 'm']);
      expect(sharesOf(e, _ids), {'j': 15000, 'm': 15000});
    });

    test('old expenses without participants are shared by everyone', () {
      final e = _expense(payer: 'j', total: 30000);
      expect(sharesOf(e, _ids), {'j': 10000, 'm': 10000, 's': 10000});
    });

    test('items go to whoever had them, tax and tip follow those shares',
        () {
      // 라멘 1,000엔(지민) + 맥주 600엔(민수·서연 반씩) + 봉사료 160엔 = 1,760엔 → 15,840원
      final e = _expense(
        payer: 'j',
        total: 1760,
        currency: Currency.of('JPY'),
        rate: _jpyRate,
        together: _ids,
        items: [
          _item('ramen', 1000, ['j']),
          _item('beer', 600, ['m', 's']),
        ],
      );
      final shares = sharesOf(e, _ids)!;
      expect(shares, {'j': 9900, 'm': 2970, 's': 2970});
      expect(shares.values.reduce((a, b) => a + b), e.totalKrw);
    });

    test('an item nobody was picked for is shared by everyone in the expense',
        () {
      final e = _expense(
        payer: 'm',
        total: 9000,
        together: ['j', 'm', 's'],
        items: [_item('side', 3000), _item('main', 6000, ['s'])],
      );
      expect(sharesOf(e, _ids), {'j': 1000, 'm': 1000, 's': 7000});
    });

    test('an expense without a rate yet is left out', () {
      final e = _expense(
          payer: 'j', total: 1800, currency: Currency.of('JPY'));
      expect(sharesOf(e, _ids), isNull);
    });
  });

  group('settle', () {
    test('everyone ends even, with as few transfers as possible', () {
      final result = settle([
        _expense(payer: 'j', total: 90000, together: _ids), // 30,000씩
        _expense(payer: 'm', total: 30000, together: ['m', 's']), // 15,000씩
        _expense(payer: 'j', total: 1800, currency: Currency.of('JPY')),
      ], _members);

      expect(result.totalKrw, 120000);
      expect(result.unratedCount, 1);
      expect([for (final b in result.balances) b.net], [60000, -15000, -45000]);
      expect(
        [for (final t in result.transfers) (t.from.name, t.to.name, t.amount)],
        [('서연', '지민', 45000), ('민수', '지민', 15000)],
      );
    });

    test('one debtor can pay several people', () {
      final result = settle([
        _expense(payer: 'j', total: 30000, together: ['j', 's']),
        _expense(payer: 'm', total: 20000, together: ['m', 's']),
      ], _members);
      expect(
        [for (final t in result.transfers) (t.from.name, t.to.name, t.amount)],
        [('서연', '지민', 15000), ('서연', '민수', 10000)],
      );
    });

    test('nothing to send when everyone paid their own share', () {
      final result = settle([
        _expense(payer: 'j', total: 10000, together: ['j']),
        _expense(payer: 'm', total: 5000, together: ['m']),
      ], _members);
      expect(result.transfers, isEmpty);
    });
  });
}
