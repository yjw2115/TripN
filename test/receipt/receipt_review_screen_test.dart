import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/receipt/presentation/receipt_review_screen.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _me = Member(id: 'me', name: '지민', uid: 'uid-me');
const _minsu = Member(id: 'g1', name: '민수');

const _thbRate = FixedRate(
    krwPerUnit: 40.12, source: RateSource.koreaexim, date: '2019-12-19');

/// Firebase 없이 그리도록 동행자 목록과 환율을 넣어 준다.
Widget _wrap(Receipt receipt,
        {List<String> warnings = const [],
        List<Member> members = const [_me],
        Future<FixedRate?> Function()? rate}) =>
    ProviderScope(
      overrides: [
        membersProvider.overrideWith((ref) => Stream.value(members)),
        myMemberProvider.overrideWith((ref) async => _me),
        rateQuoteProvider
            .overrideWith((ref, key) => rate?.call() ?? Future.value(_thbRate)),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ReceiptReviewScreen(
          args: ReviewArgs(receipt: receipt, warnings: warnings),
        ),
      ),
    );

Receipt _thaiReceipt({required int totalMinor}) => Receipt(
      merchantName: 'ต๋อง Northern Thai Cuisine',
      category: ExpenseCategory.food,
      paidAt: DateTime(2019, 12, 19, 20, 54),
      currency: Currency.of('THB'),
      items: const [
        ReceiptItem(
          id: 'i0',
          name: 'ข้าวเหนียว',
          nameKo: '찹쌀밥',
          quantity: 6,
          unitPriceMinor: 2300,
          amountMinor: 13800,
        ),
        ReceiptItem(
          id: 'i1',
          name: 'น้ำดื่ม',
          nameKo: '생수',
          quantity: 3,
          unitPriceMinor: 1000,
          amountMinor: 3000,
        ),
      ],
      totalMinor: totalMinor,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  testWidgets('shows a balanced receipt with Korean and original names',
      (tester) async {
    await tester.pumpWidget(_wrap(_thaiReceipt(totalMinor: 16800),
        warnings: ['일부 글자가 흐려요']));

    expect(find.text('฿168.00'), findsOneWidget);
    expect(find.text('품목 합계가 총액과 맞아요'), findsOneWidget);
    expect(find.text('찹쌀밥'), findsOneWidget);
    expect(find.textContaining('ข้าวเหนียว'), findsOneWidget);
    expect(find.text('일부 글자가 흐려요'), findsOneWidget);
    expect(find.text('฿168.00 저장하기'), findsOneWidget);
  });

  testWidgets('adding the missing difference balances the receipt',
      (tester) async {
    await tester.pumpWidget(_wrap(_thaiReceipt(totalMinor: 20000)));

    expect(find.text('품목 합계가 총액보다 ฿32.00 적어요'), findsOneWidget);
    await tester.tap(find.text('차액을 기타로 추가'));
    await tester.pump();

    expect(find.text('품목 합계가 총액과 맞아요'), findsOneWidget);
    expect(find.text('품목 3개'), findsOneWidget);
    expect(find.text('기타'), findsOneWidget);
  });

  testWidgets('a total-only card slip gets a neutral note, not a warning',
      (tester) async {
    await tester.pumpWidget(_wrap(Receipt(
      merchantName: '스타벅스 강남점',
      category: ExpenseCategory.cafe,
      paidAt: DateTime(2026, 10, 23, 9, 30),
      currency: Currency.krw,
      items: const [],
      totalMinor: 12500,
    )));

    expect(find.text('총액만 있는 영수증이에요'), findsOneWidget);
    expect(find.textContaining('적어요'), findsNothing);
    expect(find.text('12,500원 저장하기'), findsOneWidget);
  });

  testWidgets('a VND total typed as printed ("283.500") is read as 283,500',
      (tester) async {
    await tester.pumpWidget(_wrap(Receipt(
      merchantName: 'Quán Thử Nghiệm',
      currency: Currency.of('VND'),
      items: const [],
      totalMinor: 0,
    )));

    await tester.tap(find.text('₫0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '283.500');
    await tester.pump();
    expect(find.textContaining('₫283,500으로 저장돼요'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('₫283,500'), findsOneWidget);
  });

  testWidgets('a blank manual entry shows no check banner', (tester) async {
    await tester.pumpWidget(_wrap(const Receipt(
        merchantName: '', currency: Currency.krw, items: [], totalMinor: 0)));

    expect(find.textContaining('품목 합계'), findsNothing);
    expect(find.text('총액만 있는 영수증이에요'), findsNothing);
    expect(find.text('총 결제 금액을 입력해 주세요'), findsOneWidget);
  });

  testWidgets('shows the won amount at the fixed rate', (tester) async {
    await tester.pumpWidget(_wrap(_thaiReceipt(totalMinor: 16800)));
    await tester.pump();

    expect(find.text('≈ 6,740원'), findsOneWidget);
    expect(find.text('1바트 = 40.12원 · 12월 19일 고시'), findsOneWidget);
  });

  testWidgets('a currency without an official rate asks for one',
      (tester) async {
    await tester.pumpWidget(_wrap(
      Receipt(
          merchantName: 'Phở Hà Nội',
          currency: Currency.of('VND'),
          items: const [],
          totalMinor: 65000),
      rate: () async => null,
    ));
    await tester.pump();

    expect(find.text('환율을 정해 주세요'), findsOneWidget);
  });

  testWidgets('a won receipt shows no conversion', (tester) async {
    await tester.pumpWidget(_wrap(const Receipt(
        merchantName: '김밥천국',
        currency: Currency.krw,
        items: [],
        totalMinor: 12500)));
    await tester.pump();

    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('a solo trip does not ask who paid', (tester) async {
    await tester.pumpWidget(_wrap(_thaiReceipt(totalMinor: 16800)));
    await tester.pump();

    expect(find.text('지민 결제'), findsNothing);
    expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
  });

  testWidgets('with companions, the payer starts as me and can be changed',
      (tester) async {
    await tester.pumpWidget(
        _wrap(_thaiReceipt(totalMinor: 16800), members: const [_me, _minsu]));
    await tester.pump();

    expect(find.text('지민 결제'), findsOneWidget);
    await tester.tap(find.text('지민 결제'));
    await tester.pumpAndSettle();
    expect(find.text('누가 냈나요?'), findsOneWidget);

    await tester.tap(find.text('민수'));
    await tester.pumpAndSettle();
    expect(find.text('민수 결제'), findsOneWidget);
  });

  testWidgets('can replace the total with the item sum', (tester) async {
    await tester.pumpWidget(_wrap(_thaiReceipt(totalMinor: 10000)));

    expect(find.text('품목 합계가 총액보다 ฿68.00 많아요'), findsOneWidget);
    await tester.tap(find.text('총액을 품목 합계로 바꾸기'));
    await tester.pump();

    expect(find.text('฿168.00'), findsOneWidget);
    expect(find.text('품목 합계가 총액과 맞아요'), findsOneWidget);
  });
}
