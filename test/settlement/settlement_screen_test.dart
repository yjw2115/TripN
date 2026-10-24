import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/settlement/domain/settlement.dart';
import 'package:travelen/features/settlement/presentation/settlement_screen.dart';
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

Expense _expense(String payer, int total, List<String> together) => Expense(
      id: 'e$total',
      title: '지출',
      category: ExpenseCategory.food,
      currency: Currency.krw,
      totalMinor: total,
      paidAt: DateTime(2026, 10, 23),
      payerId: payer,
      createdBy: 'u1',
      participantIds: together,
    );

final _expenses = [
  _expense('j', 90000, ['j', 'm', 's']),
  _expense('m', 30000, ['m', 's']),
];

Widget _app() => ProviderScope(
      overrides: [
        currentTripProvider.overrideWith((ref) async => const Trip(
            id: 't', name: '도쿄 여행', ownerId: 'u1', memberUids: ['u1'])),
        membersProvider.overrideWith((ref) => Stream.value(_members)),
        expensesProvider.overrideWith((ref) => Stream.value(_expenses)),
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
