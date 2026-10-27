import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/stats/presentation/stats_screen.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(id: 'j', name: '지민', uid: 'u1');
const _minsu = Member(id: 'm', name: '민수');

Expense _expense(String id, ExpenseCategory category, int total,
        {String payer = 'j',
        List<String> together = const [],
        Currency currency = Currency.krw,
        FixedRate? rate,
        int day = 23}) =>
    Expense(
      id: id,
      title: '$id 지출',
      category: category,
      currency: currency,
      totalMinor: total,
      paidAt: DateTime(2026, 10, day, 12),
      payerId: payer,
      createdBy: 'u1',
      participantIds: together,
      rate: rate,
    );

final _expenses = [
  _expense('스시', ExpenseCategory.food, 60000),
  _expense('호텔', ExpenseCategory.lodging, 300000, payer: 'm', day: 24),
  _expense('택시', ExpenseCategory.transport, 40000, together: ['m'], day: 25),
  _expense('라멘', ExpenseCategory.food, 1000,
      currency: const Currency('JPY', 0, '¥', '엔'),
      rate: const FixedRate(krwPerUnit: 9.0, source: RateSource.koreaexim),
      day: 25),
];

Widget _app(List<Expense> expenses, {List<Member> members = const [_jimin, _minsu]}) =>
    ProviderScope(
      overrides: [
        membersProvider.overrideWith((ref) => Stream.value(members)),
        myMemberProvider.overrideWith((ref) async => _jimin),
        expensesProvider.overrideWith((ref) => Stream.value(expenses)),
      ],
      child: const MaterialApp(
        locale: Locale('ko'),
        supportedLocales: [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: StatsScreen(),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  testWidgets('shows the share of each category', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_expenses));
    await tester.pumpAndSettle();

    expect(find.text('409,000원'), findsWidgets);
    expect(find.text('어디에 썼을까'), findsOneWidget);
    // 숙소 300,000 · 식비 69,000 · 교통 40,000
    expect(find.text('73%'), findsOneWidget);
    expect(find.text('17%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('누가 얼마나 냈을까'), findsOneWidget);
    expect(find.text('화폐별'), findsOneWidget);
    expect(find.text('평균 ¥100 = 900원'), findsOneWidget);
  });

  testWidgets('picking a category narrows the big expenses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_expenses));
    await tester.pumpAndSettle();

    await tester.tap(find.text('식비').first);
    await tester.pumpAndSettle();
    expect(find.text('식비 큰 지출'), findsOneWidget);
    expect(find.text('호텔 지출'), findsNothing);

    await tester.tap(find.text('식비').first);
    await tester.pumpAndSettle();
    expect(find.text('큰 지출'), findsOneWidget);
  });

  testWidgets('my share counts only what I used', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_expenses));
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 몫'));
    await tester.pumpAndSettle();
    // 스시 30,000 + 호텔 150,000 + 라멘 4,500 (택시는 민수 혼자)
    expect(find.text('내가 쓴 돈'), findsOneWidget);
    expect(find.text('184,500원'), findsWidgets);
    expect(find.textContaining('1인 평균보다 20,000원 덜 썼어요'), findsOneWidget);
    expect(find.text('누가 얼마나 냈을까'), findsNothing);
  });

  testWidgets('a solo trip has no scope toggle or members card',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_expenses, members: const [_jimin]));
    await tester.pumpAndSettle();

    expect(find.text('내 몫'), findsNothing);
    expect(find.text('누가 얼마나 냈을까'), findsNothing);
    expect(find.text('1인 평균'), findsNothing);
  });

  testWidgets('no expenses yet', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();
    expect(find.text('아직 통계가 없어요'), findsOneWidget);
  });
}
