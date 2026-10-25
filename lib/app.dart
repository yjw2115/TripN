import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/expense/presentation/home_screen.dart';
import 'features/menu/domain/menu.dart';
import 'features/menu/presentation/menu_analyze_screen.dart';
import 'features/menu/presentation/menu_screen.dart';
import 'features/menu/presentation/menus_screen.dart';
import 'features/receipt/presentation/receipt_analyze_screen.dart';
import 'features/receipt/presentation/receipt_review_screen.dart';
import 'features/settlement/presentation/bet_game_screen.dart';
import 'features/settlement/presentation/bet_setup_screen.dart';
import 'features/settlement/presentation/settlement_screen.dart';
import 'features/trip/presentation/join_trip_screen.dart';
import 'features/trip/presentation/trip_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/analyze',
      builder: (context, state) =>
          ReceiptAnalyzeScreen(imagePaths: state.extra! as List<String>),
    ),
    GoRoute(
      path: '/review',
      builder: (context, state) =>
          ReceiptReviewScreen(args: state.extra! as ReviewArgs),
    ),
    GoRoute(path: '/trip', builder: (context, state) => const TripScreen()),
    GoRoute(path: '/menus', builder: (context, state) => const MenusScreen()),
    GoRoute(
      path: '/menu-analyze',
      builder: (context, state) =>
          MenuAnalyzeScreen(imagePaths: state.extra! as List<String>),
    ),
    GoRoute(
      path: '/menu/:menuId',
      builder: (context, state) => MenuScreen(
        menuId: state.pathParameters['menuId']!,
        args: switch (state.extra) {
          final MenuScreenArgs args => args,
          final Menu menu => MenuScreenArgs(menu: menu),
          _ => null,
        },
      ),
    ),
    GoRoute(
        path: '/settlement',
        builder: (context, state) => const SettlementScreen()),
    GoRoute(
        path: '/settlement/bet',
        builder: (context, state) => const BetSetupScreen()),
    GoRoute(
      path: '/settlement/bet/play',
      builder: (context, state) =>
          BetGameScreen(args: state.extra! as BetPlayArgs),
    ),
    GoRoute(
        path: '/join', builder: (context, state) => const JoinTripScreen()),
    // 초대 링크(https://travelen-468bc.web.app/join/{code}, tripn://app/join/{code})가 여기로 온다.
    // /join 아래에 겹치지 않게 따로 두어서, 닫으면 코드 입력 화면이 아니라 홈으로 간다.
    GoRoute(
      path: '/join/:code',
      builder: (context, state) =>
          JoinTripScreen(initialCode: state.pathParameters['code']),
    ),
  ],
);

class TravelenApp extends StatelessWidget {
  const TravelenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '여행N',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
