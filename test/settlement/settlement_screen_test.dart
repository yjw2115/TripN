import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/features/expense/data/expense_repository.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/settlement/domain/bet.dart';
import 'package:travelen/features/settlement/domain/settlement.dart';
import 'package:travelen/features/settlement/presentation/settlement_screen.dart';
import 'package:travelen/features/trip/data/trip_repository.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(
  id: 'j',
  name: '지민',
  uid: 'u1',
  account: BankAccount(bank: '카카오뱅크', number: '3333-01-1234567', holder: '김지민'),
);
const _minsu = Member(id: 'm', name: '민수');
const _seoyeon = Member(id: 's', name: '서연');
const _members = [_jimin, _minsu, _seoyeon];

Expense _expense(String payer, int total, List<String> together,
        {DateTime? settledAt}) =>
    Expense(
      id: 'e$total',
      title: '지출',
      category: ExpenseCategory.food,
      currency: Currency.krw,
      totalMinor: total,
      paidAt: DateTime(2026, 10, 23),
      payerId: payer,
      createdBy: 'u1',
      participantIds: together,
      settledAt: settledAt,
    );

final _expenses = [
  _expense('j', 90000, ['j', 'm', 's']),
  _expense('m', 30000, ['m', 's']),
];

Widget _app(
        [List<Expense>? expenses,
        SettlementBet? bet,
        TripRepository? repository,
        ExpenseRepository? expenseRepository]) =>
    ProviderScope(
      overrides: [
        currentTripProvider.overrideWith((ref) async => Trip(
            id: 't',
            name: '도쿄 여행',
            ownerId: 'u1',
            memberUids: const ['u1'],
            settlementBet: bet)),
        membersProvider.overrideWith((ref) => Stream.value(_members)),
        expensesProvider
            .overrideWith((ref) => Stream.value(expenses ?? _expenses)),
        if (repository != null)
          tripRepositoryProvider.overrideWithValue(repository),
        if (expenseRepository != null)
          expenseRepositoryProvider.overrideWithValue(expenseRepository),
      ],
      child: const MaterialApp(
        locale: Locale('ko'),
        supportedLocales: [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: SettlementScreen(),
      ),
    );

void main() {
  testWidgets('shows who sends whom how much, and each balance',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('120,000원'), findsOneWidget);
    expect(find.text('서연 → 지민'), findsOneWidget);
    expect(find.text('45,000원'), findsOneWidget);
    expect(find.text('민수 → 지민'), findsOneWidget);
    expect(find.text('60,000원 받을 돈'), findsOneWidget);
    expect(find.text('45,000원 보낼 돈'), findsOneWidget);
  });

  testWidgets("copies the receiver's account with the amount", (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('서연 → 지민'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계좌와 금액 복사'));
    await tester.pumpAndSettle();

    expect(copied, '카카오뱅크 3333-01-1234567 김지민 45,000원');
    expect(find.text('계좌와 금액을 복사했어요'), findsOneWidget);
  });

  group('local currency', () {
    // 도쿄: 엔화 지출 18,000엔(100엔 = 900원) + 원화 지출
    final jpy = Expense(
      id: 'ramen',
      title: '라멘',
      category: ExpenseCategory.food,
      currency: Currency.of('JPY'),
      totalMinor: 18000,
      paidAt: DateTime(2026, 10, 23),
      payerId: 'j',
      createdBy: 'u1',
      participantIds: const ['j', 'm', 's'],
      rate: const FixedRate(krwPerUnit: 9, source: RateSource.koreaexim),
    );
    final tokyo = [jpy, _expense('m', 30000, ['m', 's'])];

    test('the most spent foreign currency comes first at its average rate', () {
      final thb = Expense(
        id: 'tuktuk',
        title: '툭툭',
        category: ExpenseCategory.transport,
        currency: Currency.of('THB'),
        totalMinor: 10000, // ฿100
        paidAt: DateTime(2026, 10, 23),
        payerId: 'j',
        createdBy: 'u1',
        rate: const FixedRate(krwPerUnit: 40, source: RateSource.koreaexim),
      );
      final options = localCurrenciesOf([thb, ...tokyo]);
      expect([for (final o in options) o.currency.code], ['JPY', 'THB']);
      expect(options.first.krwPerUnit, 9);
      expect(options.first.fromKrw(54000), 6000);
    });

    testWidgets('amounts show in yen too, but copying stays in won',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await tester.pumpWidget(_app(tokyo));
      await tester.pumpAndSettle();

      // 총 192,000원 = ¥21,333 / 서연 → 지민 69,000원 = ¥7,667
      expect(find.text('≈ ¥21,333'), findsOneWidget);
      expect(find.text('서연 → 지민'), findsOneWidget);
      expect(find.text('≈ ¥7,667'), findsWidgets);

      await tester.tap(find.text('서연 → 지민'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('금액 복사'));
      await tester.pumpAndSettle();
      expect(copied, '69000');

      // 드롭다운을 열고 원화만 고른다 (닫힌 버튼도 모든 항목을 품고 있어서 마지막 것이 메뉴다).
      expect(find.text('🇯🇵'), findsWidgets);
      await tester.tap(find.text('엔 JPY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('원화만').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('≈ ¥'), findsNothing);
    });
  });

  group('mini-game bet', () {
    // 민수가 낸 30,000원(민수·서연)을 서연이 쏜다.
    const bet = SettlementBet(
      game: BetGame.wave,
      stake: TreatStake('e30000'),
      loserId: 's',
      participantIds: ['j', 'm', 's'],
    );

    testWidgets('without a bet the card offers a game', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('미니게임으로 정하기'), findsOneWidget);
    });

    testWidgets('a bet changes who sends what, and can be undone',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('trips/t').set({
        'name': '도쿄 여행',
        'ownerId': 'u1',
        'memberUids': ['u1'],
        'settlementBet': bet.toMap(),
      });
      await tester.pumpWidget(_app(null, bet, TripRepository(db)));
      await tester.pumpAndSettle();

      expect(find.text('파도타기로 정했어요'), findsOneWidget);
      expect(find.text("서연님이 '지출'을 쏴요"), findsOneWidget);
      expect(find.text('15,000원 더 내요'), findsOneWidget);
      // 민수는 보낼 돈이 없어지고, 서연이 민수 몫까지 지민에게 보낸다.
      expect(find.text('서연 → 지민'), findsOneWidget);
      expect(find.text('민수 → 지민'), findsNothing);
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.textContaining('내기 +15,000원'), findsOneWidget);

      await tester.tap(find.text('원래 정산으로'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect((await db.doc('trips/t').get()).data()!.containsKey('settlementBet'),
          isFalse);
    });
  });

  group('settling early', () {
    /// 지출 문서가 있어야 정산 완료로 표시할 수 있다.
    Future<FakeFirebaseFirestore> seeded() async {
      final db = FakeFirebaseFirestore();
      await db.doc('trips/t').set({
        'name': '도쿄 여행',
        'ownerId': 'u1',
        'memberUids': ['u1'],
      });
      for (final e in _expenses) {
        await db.doc('trips/t/expenses/${e.id}').set({'totalMinor': e.totalMinor});
      }
      return db;
    }

    Future<Map<String, dynamic>> expenseDoc(
            FakeFirebaseFirestore db, String id) async =>
        (await db.doc('trips/t/expenses/$id').get()).data()!;

    testWidgets('picks some expenses, settles just those, and marks them done',
        (tester) async {
      final db = await seeded();
      await tester.pumpWidget(_app(null, null, null, ExpenseRepository(db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('지출 고르기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10월 23일 · 30,000원'));
      await tester.pump();
      await tester.tap(find.text('1건 · 90,000원 정산하기'));
      await tester.pumpAndSettle();

      // 90,000원을 셋이 → 민수·서연이 지민에게 30,000원씩
      expect(find.text('고른 지출'), findsOneWidget);
      expect(find.text('3명 · 지출 1건 · 고르지 않은 1건은 빠져 있어요'),
          findsOneWidget);
      expect(find.text('서연 → 지민'), findsOneWidget);
      expect(find.text('민수 → 지민'), findsOneWidget);
      expect(find.text('30,000원'), findsNWidgets(2));

      await tester.tap(find.text('정산 완료'));
      await tester.pumpAndSettle();
      expect(find.text('지출 1건을 정산 완료로 할까요?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '정산 완료'));
      await tester.pumpAndSettle();

      expect(find.text('지출 1건을 정산했어요'), findsOneWidget);
      expect((await expenseDoc(db, 'e90000'))['settledAt'], isA<String>());
      expect((await expenseDoc(db, 'e30000')).containsKey('settledAt'), isFalse);
    });

    testWidgets('an applied bet is used up by the settlement it went into',
        (tester) async {
      const bet = SettlementBet(
        game: BetGame.wave,
        stake: ChangeStake(10000),
        loserId: 's',
        participantIds: ['j', 'm', 's'],
      );
      final db = await seeded();
      await db.doc('trips/t').update({'settlementBet': bet.toMap()});
      await tester.pumpWidget(
          _app(null, bet, TripRepository(db), ExpenseRepository(db)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('정산 완료'));
      await tester.pumpAndSettle();
      expect(find.textContaining('게임 결과도 이번 정산에 넣고 지워요'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '정산 완료'));
      await tester.pumpAndSettle();

      expect((await db.doc('trips/t').get()).data()!.containsKey('settlementBet'),
          isFalse);
      expect((await expenseDoc(db, 'e90000'))['settledAt'], isA<String>());
      expect((await expenseDoc(db, 'e30000'))['settledAt'], isA<String>());
    });

    testWidgets('settled expenses stay out and can be brought back',
        (tester) async {
      final db = await seeded();
      final at = DateTime(2026, 10, 24, 21, 5);
      await db
          .doc('trips/t/expenses/e30000')
          .update({'settledAt': at.toIso8601String()});
      await tester.pumpWidget(_app([
        _expenses[0],
        _expense('m', 30000, ['m', 's'], settledAt: at),
      ], null, null, ExpenseRepository(db)));
      await tester.pumpAndSettle();

      expect(find.text('90,000원'), findsOneWidget);
      expect(find.text('미리 정산한 지출 1건은 빠져 있어요'), findsOneWidget);
      await tester.tap(find.text('보기'));
      await tester.pumpAndSettle();
      expect(find.text('10월 24일 21:05 정산'), findsOneWidget);

      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect(find.text('이 정산을 되돌릴까요?'), findsOneWidget);
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect((await expenseDoc(db, 'e30000')).containsKey('settledAt'), isFalse);
    });
  });

  test('the request message lists transfers and accounts', () {
    final message = settlementMessage('도쿄 여행', settle(_expenses, _members));
    expect(
      message,
      "[여행N] '도쿄 여행' 정산\n"
      '총 지출 120,000원 · 3명\n'
      '\n'
      '서연 → 지민 45,000원\n'
      '민수 → 지민 15,000원\n'
      '\n'
      '받을 계좌\n'
      '지민: 카카오뱅크 3333-01-1234567 김지민',
    );
  });

  test('item participants in a receipt carry through to the settlement', () {
    final expense = Expense(
      id: 'r',
      title: '라멘집',
      category: ExpenseCategory.food,
      currency: Currency.krw,
      totalMinor: 30000,
      paidAt: DateTime(2026, 10, 23),
      payerId: 'j',
      createdBy: 'u1',
      participantIds: const ['j', 'm', 's'],
      receipt: const Receipt(
        merchantName: '라멘집',
        currency: Currency.krw,
        items: [
          ReceiptItem(id: 'a', name: '라멘', amountMinor: 12000, participantIds: ['m']),
          ReceiptItem(id: 'b', name: '교자', amountMinor: 18000),
        ],
        totalMinor: 30000,
      ),
    );
    final result = settle([expense], _members);
    expect([for (final b in result.balances) b.owed], [6000, 18000, 6000]);
  });
}
