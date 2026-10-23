import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/expense/presentation/home_screen.dart';
import 'features/receipt/presentation/receipt_analyze_screen.dart';
import 'features/receipt/presentation/receipt_review_screen.dart';

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
