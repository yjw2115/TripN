import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/core/money/exchange_rate.dart';
import 'package:travelen/features/menu/domain/menu.dart';
import 'package:travelen/features/menu/presentation/menu_screen.dart';
import 'package:travelen/features/receipt/domain/receipt_validator.dart';
import 'package:travelen/features/receipt/presentation/receipt_review_screen.dart';

Menu _menu({String country = 'JP', bool taxIncluded = false, double taxRate = 10}) => Menu(
      id: 'm1',
      storeName: '이치란',
      currency: Currency.of(country == 'US' ? 'USD' : 'JPY'),
      countryCode: country,
      taxIncluded: taxIncluded,
      taxRatePercent: taxRate,
      items: const [
        MenuItem(
            id: 'a',
            name: 'ラーメン',
            nameKo: '라멘',
            descriptionKo: '돼지 뼈 육수 라멘',
            priceMinor: 1000,
            section: '라멘'),
        MenuItem(id: 'b', name: '生ビール', nameKo: '생맥주', priceMinor: 600, section: '음료'),
      ],
    );

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  ReviewArgs? reviewed;

  Widget app(Menu menu) => ProviderScope(
        overrides: [
          menuProvider.overrideWith((ref, id) => Stream.value(menu)),
          rateQuoteProvider.overrideWith((ref, key) async => const FixedRate(
              krwPerUnit: 9, source: RateSource.koreaexim, date: '2026-10-23')),
        ],
        child: MaterialApp.router(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: GoRouter(initialLocation: '/menu/m1', routes: [
            GoRoute(
                path: '/menu/:id',
                builder: (_, state) =>
                    MenuScreen(menuId: state.pathParameters['id']!)),
            GoRoute(
                path: '/review',
                builder: (_, state) {
                  reviewed = state.extra! as ReviewArgs;
                  return const Text('영수증 확인');
                }),
          ]),
        ),
      );

  setUp(() => reviewed = null);

  testWidgets('shows the translated menu with won prices', (tester) async {
    await tester.pumpWidget(app(_menu()));
    await tester.pumpAndSettle();

    expect(find.text('라멘'), findsWidgets); // 구역 이름과 메뉴 이름
    expect(find.text('ラーメン'), findsOneWidget);
    expect(find.text('돼지 뼈 육수 라멘'), findsOneWidget);
    expect(find.textContaining('≈ 9,000원'), findsOneWidget);
    expect(find.text('메뉴를 고르면 합계를 미리 계산해 드려요'), findsOneWidget);
  });

  testWidgets('picking dishes builds a preview receipt that records as an expense',
      (tester) async {
    await tester.pumpWidget(app(_menu()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('라멘 담기'));
    await tester.pump();
    await tester.tap(find.byTooltip('라멘 더 담기'));
    await tester.tap(find.byTooltip('생맥주 담기'));
    await tester.pump();
    // ¥2,600 + 세금 10% = ¥2,860 ≈ 25,740원
    expect(find.text('3개'), findsOneWidget);
    expect(find.text('¥2,860 · ≈ 25,740원'), findsOneWidget);

    await tester.tap(find.text('미리 보는 영수증'));
    await tester.pumpAndSettle();
    expect(find.text('¥1,000 × 2'), findsOneWidget);
    expect(find.text('세금 10% (별도)'), findsOneWidget);
    expect(find.text('¥260'), findsOneWidget);

    await tester.tap(find.text('¥2,860 이대로 기록하기'));
    await tester.pumpAndSettle();
    expect(find.text('영수증 확인'), findsOneWidget);
    final receipt = reviewed!.receipt;
    expect(reviewed!.source, 'menu');
    expect((receipt.merchantName, receipt.totalMinor, receipt.items.length),
        ('이치란', 2860, 2));
    expect(checkReceipt(receipt).totalMatches, isTrue);
  });

  testWidgets('in the US the tip can be picked as a percentage', (tester) async {
    await tester.pumpWidget(app(_menu(country: 'US', taxRate: 8)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('라멘 담기'));
    await tester.pump();
    await tester.tap(find.text('미리 보는 영수증'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20%'));
    await tester.pump();
    // $10.00 + 세금 8% $0.80 + 팁 20% $2.00 = $12.80
    expect(find.text('\$12.80 이대로 기록하기'), findsOneWidget);
  });
}
