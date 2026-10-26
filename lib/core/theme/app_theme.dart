import 'package:flutter/material.dart';

import 'app_icons.dart';

/// 노란 기가 도는 따뜻한 파스텔 초록(피스타치오)을 중심으로 한 색 팔레트.
///
/// 파스텔 초록([primary]) 위에 흰 글자는 대비가 1.4:1밖에 안 돼서 읽기 어렵다.
/// 그래서 채움색 위 글자는 [onPrimary](약 8.8:1), 흰 바탕 위 링크·아이콘은
/// [primaryDeep](약 5.2:1)을 쓴다.
abstract final class AppColors {
  static const primary = Color(0xFFB9E4A7);
  static const onPrimary = Color(0xFF213A16);
  static const primaryDeep = Color(0xFF3F7A2A);
  static const primaryLight = Color(0xFFF2F9EC);
  static const background = Color(0xFFF2F4F6);
  static const surface = Colors.white;
  static const text = Color(0xFF191F28);
  static const textSub = Color(0xFF4E5968);
  static const textHint = Color(0xFF8B95A1);
  static const border = Color(0xFFE5E8EB);
  static const success = primaryDeep;
  static const successLight = primaryLight;
  static const warning = Color(0xFFFF8A00);
  static const warningLight = Color(0xFFFFF3E0);
  static const danger = Color(0xFFF04452);
}

ThemeData buildAppTheme() {
  const font = 'Pretendard';
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: font,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      // 스위치·로딩 표시처럼 흰 바탕 위에 그려지는 강조색은 짙은 초록.
      primary: AppColors.primaryDeep,
      primaryContainer: AppColors.primary,
      onPrimaryContainer: AppColors.onPrimary,
      secondaryContainer: AppColors.primaryLight,
      onSecondaryContainer: AppColors.primaryDeep,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.background,
    // 머티리얼 물결 대신, 누른 동안만 살짝 어두워진다.
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x0F000000),
    hoverColor: Colors.transparent,
    // 안드로이드도 iOS처럼 옆으로 밀려 들어오고, 왼쪽 끝을 밀어 뒤로 간다.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
  return base.copyWith(
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(AppIcons.chevronLeft, size: 24),
      closeButtonIconBuilder: (_) => const Icon(AppIcons.close, size: 22),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: font,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textHint,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryDeep,
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      hintStyle: const TextStyle(color: AppColors.textHint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryDeep, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      dragHandleColor: AppColors.border,
      dragHandleSize: Size(36, 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
