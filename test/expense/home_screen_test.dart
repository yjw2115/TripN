import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/expense/presentation/home_screen.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(id: 'j', name: '지민', uid: 'u1');
const _minsu = Member(id: 'm', name: '민수');

Expense _expense(String title, String payer, {Receipt? receipt, int day = 23}) =>
    Expense(
      id: title,
      title: title,
      category: ExpenseCategory.food,
      currency: Currency.krw,
      totalMinor: 10000,
      paidAt: DateTime(2026, 10, day, 12),
      payerId: payer,
      createdBy: 'u1',
      receipt: receipt,
    );

final _expenses = [
  _expense('스시', 'j',
      receipt: const Receipt(
        merchantName: '스시잔마이',
        currency: Currency.krw,
        items: [
          ReceiptItem(id: 'i1', name: 'マグロ', nameKo: '참치', amountMinor: 10000),
        ],
        totalMinor: 10000,
      )),
  _expense('택시', 'm', day: 24),
  _expense('편의점', 'm', day: 24),
];

Widget _app({List<Member> members = const [_jimin, _minsu]}) => ProviderScope(
      overrides: [
        membersProvider.overrideWith((ref) => Stream.value(members)),
        expensesProvider.overrideWith((ref) => Stream.value(_expenses)),
        rateBackfillProvider.overrideWith((ref) {}),
      ],
      child: const MaterialApp(
        locale: Locale('ko'),
        supportedLocales: [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeScreen(),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  Future<void> pump(WidgetTester tester, {List<Member>? members}) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(members == null ? _app() : _app(members: members));
    await tester.pumpAndSettle();
  }

  testWidgets('filters the list by who paid', (tester) async {
    await pump(tester);
    expect(find.text('정산하기'), findsOneWidget);
    expect(find.text('스시'), findsOneWidget);
    expect(find.text('택시'), findsOneWidget);

    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('민수 결제'));
    await tester.pumpAndSettle();

    expect(find.text('민수 결제'), findsOneWidget);
    expect(find.text('스시'), findsNothing);
    expect(find.text('택시'), findsOneWidget);
    expect(find.text('편의점'), findsOneWidget);
    // 요약 합계는 거르기와 상관없이 여행 전체.
    expect(find.text('지출 3건'), findsOneWidget);

    await tester.tap(find.text('민수 결제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체').last);
    await tester.pumpAndSettle();
    expect(find.text('스시'), findsOneWidget);
  });

  testWidgets('searches titles, shops and item names', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('지출 검색'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '참치');
    await tester.pumpAndSettle();
    expect(find.text('스시'), findsOneWidget);
    expect(find.text('택시'), findsNothing);

    await tester.enterText(find.byType(TextField), '편의');
    await tester.pumpAndSettle();
    expect(find.text('편의점'), findsOneWidget);
    expect(find.text('스시'), findsNothing);

    await tester.enterText(find.byType(TextField), '없는 이름');
    await tester.pumpAndSettle();
    expect(find.text("'없는 이름' 검색 결과가 없어요"), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('택시'), findsOneWidget);
  });

  testWidgets('a solo trip has no payer filter', (tester) async {
    await pump(tester, members: const [_jimin]);
    expect(find.text('지출 내역'), findsOneWidget);
    expect(find.text('전체'), findsNothing);
    expect(find.text('동행자 추가'), findsOneWidget);
    expect(find.text('택시'), findsOneWidget);
  });
}
