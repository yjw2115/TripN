import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/receipt/presentation/receipt_review_screen.dart';

Widget _wrap(Receipt receipt, {List<String> warnings = const []}) =>
    ProviderScope(
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

  testWidgets('can replace the total with the item sum', (tester) async {
    await tester.pumpWidget(_wrap(_thaiReceipt(totalMinor: 10000)));

    expect(find.text('품목 합계가 총액보다 ฿68.00 많아요'), findsOneWidget);
    await tester.tap(find.text('총액을 품목 합계로 바꾸기'));
    await tester.pump();

    expect(find.text('฿168.00'), findsOneWidget);
    expect(find.text('품목 합계가 총액과 맞아요'), findsOneWidget);
  });
}
