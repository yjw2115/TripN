import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/features/expense/data/exchange_rate_repository.dart';
import 'package:travelen/features/expense/data/expense_repository.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/trip/domain/trip.dart';

final _jpy = Currency.of('JPY');
final _usd = Currency.of('USD');
final _vnd = Currency.of('VND');

const _friday = {
  'effectiveDate': '2026-10-23',
  'krwPer': {'USD': 1385.5, 'JPY': 9.2512, 'CNH': 190.2},
};

void main() {
  group('FixedRate', () {
    test('converts minor units to whole won', () {
      const rate = FixedRate(krwPerUnit: 9.2512, source: RateSource.koreaexim);
      expect(rate.toKrw(1800, _jpy), 16652);
      const usd = FixedRate(krwPerUnit: 1385.5, source: RateSource.koreaexim);
      expect(usd.toKrw(1250, _usd), 17319); // $12.50
    });

    test('a half won rounds up even when the rate is not exact in binary', () {
      const vnd = FixedRate(krwPerUnit: 54.3 / 1000, source: RateSource.manual);
      expect(vnd.toKrw(65000, _vnd), 3530); // 3,529.5원
    });

    test('formats rates per a readable unit', () {
      expect(
          formatRate(
              const FixedRate(krwPerUnit: 9.2512, source: RateSource.koreaexim),
              _jpy),
          '100엔 = 925.12원');
      expect(
          formatRate(
              const FixedRate(krwPerUnit: 0.0543, source: RateSource.manual),
              _vnd),
          '1,000동 = 54.3원');
    });

    test('expenses without a rate read as unknown, except won', () {
      Expense expense(String currency, Map<String, Object?> extra) =>
          Expense.fromMap('e', {
            'currency': currency,
            'totalMinor': 1800,
            'paidAt': '2026-10-23T12:00:00',
            ...extra,
          });
      expect(expense('JPY', {}).totalKrw, isNull);
      expect(expense('KRW', {}).totalKrw, 1800);
      final fixed = expense('JPY', {
        'krwRate': 9.2512,
        'rateSource': 'koreaexim',
        'rateDate': '2026-10-23',
      });
      expect(fixed.totalKrw, 16652);
      expect(fixed.rate?.date, '2026-10-23');
    });
  });

  group('rateDateKey', () {
    // 2026-10-24 10:00 KST
    final now = DateTime.utc(2026, 10, 24, 1);

    test('uses the receipt date as printed', () {
      expect(rateDateKey(DateTime(2026, 10, 20, 23, 50), now: now),
          '2026-10-20');
    });

    test('a date ahead of Seoul (e.g. New Zealand) becomes Seoul today', () {
      expect(rateDateKey(DateTime(2026, 10, 25, 9), now: now), '2026-10-24');
    });
  });

  group('ExchangeRateRepository', () {
    late FakeFirebaseFirestore db;
    late List<String> calls;
    late ExchangeRateRepository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      calls = [];
      repo = ExchangeRateRepository(db, (date) async {
        calls.add(date);
        return _friday;
      });
    });

    test('reads cached rates without calling the function', () async {
      // 일요일 문서도 금요일 환율을 가리킨다 (함수가 저장해 둔다).
      await db.doc('rates/2026-10-18').set(_friday);
      final rate = await repo.rateFor(_jpy, DateTime(2026, 10, 18, 13));
      expect((rate?.krwPerUnit, rate?.date, rate?.source),
          (9.2512, '2026-10-23', RateSource.koreaexim));
      expect(calls, isEmpty);
    });

    test('calls the function when the date is not cached yet', () async {
      final rate = await repo.rateFor(_usd, DateTime(2026, 10, 23));
      expect(rate?.krwPerUnit, 1385.5);
      expect(calls, ['2026-10-23']);
    });

    test('yuan is looked up as offshore yuan (CNH)', () async {
      final rate = await repo.rateFor(Currency.of('CNY'), DateTime(2026, 10, 23));
      expect(rate?.krwPerUnit, 190.2);
    });

    test('won needs no lookup', () async {
      expect(await repo.rateFor(Currency.krw, DateTime(2026, 10, 23)),
          FixedRate.krw);
      expect(calls, isEmpty);
    });

    test('a currency without an official rate uses the trip rate, or asks',
        () async {
      expect(await repo.rateFor(_vnd, DateTime(2026, 10, 23)), isNull);
      final manual = await repo.rateFor(_vnd, DateTime(2026, 10, 23),
          manualRates: {'VND': 0.0543});
      expect((manual?.krwPerUnit, manual?.source),
          (0.0543, RateSource.manual));
    });

    test('offline, a trip rate still works but official ones fail', () async {
      final offline = ExchangeRateRepository(
          db, (_) async => throw Exception('unavailable'));
      final manual = await offline.rateFor(_vnd, DateTime(2026, 10, 23),
          manualRates: {'VND': 0.0543});
      expect(manual?.source, RateSource.manual);
      expect(offline.rateFor(_jpy, DateTime(2026, 10, 23)), throwsException);
    });
  });

  group('saving expenses', () {
    late FakeFirebaseFirestore db;
    late ExpenseRepository repo;
    final receipt = Receipt(
      merchantName: '라멘집',
      paidAt: DateTime(2026, 10, 23, 12),
      currency: _jpy,
      items: const [],
      totalMinor: 1800,
    );
    const rate = FixedRate(
        krwPerUnit: 9.2512, source: RateSource.koreaexim, date: '2026-10-23');

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = ExpenseRepository(db);
    });

    Future<Expense> only() async =>
        (await repo.watchExpenses('t1').first).single;

    test('the rate is fixed at save time and kept on unrelated edits',
        () async {
      await repo.saveReceipt(
          tripId: 't1', uid: 'a', payerId: 'a', participantIds: const ['a'], receipt: receipt, rate: rate);
      final saved = await only();
      expect(saved.totalKrw, 16652);

      await repo.saveReceipt(
          tripId: 't1',
          uid: 'a',
          payerId: 'a',
          participantIds: const ['a'],
          receipt: receipt.copyWith(merchantName: '돈코츠 라멘'),
          expenseId: saved.id,
          keepRate: true);
      expect((await only()).rate?.krwPerUnit, 9.2512);
    });

    test('a new date without a rate clears the old one for backfill',
        () async {
      await repo.saveReceipt(
          tripId: 't1', uid: 'a', payerId: 'a', participantIds: const ['a'], receipt: receipt, rate: rate);
      final saved = await only();

      await repo.saveReceipt(
          tripId: 't1',
          uid: 'a',
          payerId: 'a',
          participantIds: const ['a'],
          receipt: receipt.copyWith(paidAt: DateTime(2026, 10, 26)),
          expenseId: saved.id);
      expect((await only()).rate, isNull);

      await repo.fillRate('t1', saved.id, rate);
      expect((await only()).totalKrw, 16652);
    });
  });

  test('the backfill fills expenses saved without a rate', () async {
    final db = FakeFirebaseFirestore();
    final expenses = ExpenseRepository(db);
    await db.doc('rates/2026-10-23').set(_friday);
    await expenses.saveReceipt(
      tripId: 't1',
      uid: 'a',
      payerId: 'a',
      participantIds: const ['a'],
      receipt: Receipt(
        merchantName: '라멘집',
        paidAt: DateTime(2026, 10, 23, 12),
        currency: _jpy,
        items: const [],
        totalMinor: 1800,
      ),
    );

    final container = ProviderContainer(overrides: [
      expenseRepositoryProvider.overrideWithValue(expenses),
      exchangeRateRepositoryProvider.overrideWithValue(
          ExchangeRateRepository(db, (_) async => _friday)),
      currentTripProvider.overrideWith((ref) async => const Trip(
          id: 't1', name: '도쿄', ownerId: 'a', memberUids: ['a'])),
      expensesProvider.overrideWith((ref) => expenses.watchExpenses('t1')),
    ]);
    addTearDown(container.dispose);
    container.listen(currentTripProvider, (_, _) {});
    final sub = container.listen(expensesProvider, (_, _) {});
    await container.read(currentTripProvider.future);
    await container.read(expensesProvider.future);

    container.read(rateBackfillProvider);
    await pumpEventQueue();

    expect(sub.read().value?.single.totalKrw, 16652);
  });
}
