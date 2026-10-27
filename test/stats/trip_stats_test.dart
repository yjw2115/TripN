import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/core/money/money_format.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/stats/domain/trip_stats.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(id: 'j', name: '지민', uid: 'u1');
const _minsu = Member(id: 'm', name: '민수');
const _seoyeon = Member(id: 's', name: '서연');
const _members = [_jimin, _minsu, _seoyeon];

const _jpy = Currency('JPY', 0, '¥', '엔');
const _jpyRate = FixedRate(krwPerUnit: 9.0, source: RateSource.koreaexim);

var _seq = 0;

Expense _expense(
  ExpenseCategory category,
  int total, {
  String payer = 'j',
  DateTime? paidAt,
  Currency currency = Currency.krw,
  FixedRate? rate,
  List<String> together = const [],
  DateTime? settledAt,
}) =>
    Expense(
      id: 'e${_seq++}',
      title: category.label,
      category: category,
      currency: currency,
      totalMinor: total,
      paidAt: paidAt ?? DateTime(2026, 10, 23, 12),
      payerId: payer,
      createdBy: 'u1',
      participantIds: together,
      settledAt: settledAt,
      rate: rate,
    );

void main() {
  group('categories', () {
    test('biggest category first, percents add up to 100', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 10000),
        _expense(ExpenseCategory.food, 23333),
        _expense(ExpenseCategory.lodging, 33333),
        _expense(ExpenseCategory.transport, 33334),
      ], _members);
      expect(stats.totalKrw, 100000);
      expect([for (final c in stats.categories) c.category], [
        ExpenseCategory.transport,
        ExpenseCategory.food,
        ExpenseCategory.lodging,
      ]);
      expect([for (final c in stats.categories) c.count], [1, 2, 1]);
      expect(stats.categories.fold(0, (sum, c) => sum + c.percent), 100);
      expect([for (final c in stats.categories) c.percent], [34, 33, 33]);
    });

    test('a tiny category can round to 0%', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 100000),
        _expense(ExpenseCategory.cafe, 300),
      ], _members);
      expect(stats.categories.last.category, ExpenseCategory.cafe);
      expect(stats.categories.last.percent, 0);
      expect(stats.categories.first.percent, 100);
    });

    test('unrated expenses are left out and counted', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 10000),
        _expense(ExpenseCategory.shopping, 5000, currency: _jpy),
        _expense(ExpenseCategory.shopping, 1000, currency: _jpy, rate: _jpyRate),
      ], _members);
      expect(stats.unratedCount, 1);
      expect(stats.totalKrw, 19000);
      expect(stats.count, 2);
    });

    test('settled expenses still count as spending', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 10000, settledAt: DateTime(2026, 10, 24)),
      ], _members);
      expect(stats.totalKrw, 10000);
    });
  });

  group('my share', () {
    test('counts only my part of each expense', () {
      final expenses = [
        _expense(ExpenseCategory.food, 30000), // 셋이 10,000씩
        _expense(ExpenseCategory.lodging, 20000, together: ['j', 'm']),
        _expense(ExpenseCategory.transport, 9000, together: ['m', 's']),
      ];
      final mine = tripStats(expenses, _members, memberId: 'j');
      expect(mine.totalKrw, 20000);
      expect(mine.count, 2);
      expect({for (final c in mine.categories) c.category: c.krw}, {
        ExpenseCategory.food: 10000,
        ExpenseCategory.lodging: 10000,
      });
      expect([for (final c in mine.categories) c.percent], [50, 50]);
      expect(mine.spends.first.krw, 10000);
      expect(mine.currencies, isEmpty);
    });
  });

  group('members', () {
    test('paid and used across the whole trip', () {
      final expenses = [
        _expense(ExpenseCategory.food, 30000),
        _expense(ExpenseCategory.transport, 9000,
            payer: 'm', together: ['m', 's']),
      ];
      final stats = tripStats(expenses, _members, memberId: 's');
      final byId = {for (final m in stats.members) m.member.id: m};
      expect(byId['j']!.paid, 30000);
      expect(byId['j']!.used, 10000);
      expect(byId['m']!.paid, 9000);
      expect(byId['m']!.used, 14500);
      expect(byId['s']!.paid, 0);
      expect(byId['s']!.used, 14500);
    });
  });

  group('days', () {
    test('fills the days between with nothing spent', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 10000, paidAt: DateTime(2026, 10, 30, 9)),
        _expense(ExpenseCategory.cafe, 5000, paidAt: DateTime(2026, 10, 30, 15)),
        _expense(ExpenseCategory.lodging, 80000, paidAt: DateTime(2026, 11, 2, 22)),
      ], _members);
      expect([for (final d in stats.days) d.day], [
        DateTime(2026, 10, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 2),
      ]);
      expect([for (final d in stats.days) d.krw], [15000, 0, 0, 80000]);
      expect(stats.days.first.topCategory, ExpenseCategory.food);
      expect(stats.days[1].topCategory, isNull);
      expect(stats.peakDay!.day, DateTime(2026, 11, 2));
      expect(stats.perDay, 95000 ~/ 4);
    });

    test('a far-off date keeps only the days with spending', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 10000, paidAt: DateTime(2000)),
        _expense(ExpenseCategory.food, 10000, paidAt: DateTime(2026, 10, 23)),
      ], _members);
      expect(stats.days.length, 2);
    });
  });

  group('currencies', () {
    test('local totals, average rate and share of the won total', () {
      final stats = tripStats([
        _expense(ExpenseCategory.food, 1000, currency: _jpy, rate: _jpyRate),
        _expense(ExpenseCategory.food, 3000,
            currency: _jpy,
            rate: const FixedRate(krwPerUnit: 10.0, source: RateSource.koreaexim)),
        _expense(ExpenseCategory.transport, 1000),
      ], _members);
      final jpy = stats.currencies.first;
      expect(jpy.currency.code, 'JPY');
      expect(jpy.minor, 4000);
      expect(jpy.krw, 39000);
      expect(jpy.krwPerUnit, 9.75);
      expect(jpy.percent, 98);
      expect(stats.currencies.last.currency, Currency.krw);
      expect(stats.currencies.last.percent, 2);
    });
  });

  test('formatWonCompact', () {
    expect(formatWonCompact(9800), '9,800');
    expect(formatWonCompact(45000), '4.5만');
    expect(formatWonCompact(120000), '12만');
    expect(formatWonCompact(1234567), '123만');
    expect(formatWonCompact(123000000), '1.2억');
  });
}
