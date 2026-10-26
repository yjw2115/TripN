import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable.dart';

/// 확인을 받는 대화상자 (머티리얼 AlertDialog 대신). 확인을 누르면 true.
/// [destructive]면 확인 버튼이 빨간색이다 (지우기·나가기).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  String cancelLabel = '취소',
  bool destructive = false,
}) async {
  final confirmed = await _show<bool>(
    context,
    title: title,
    body: body,
    buttons: (context) => [
      _DialogButton(
        label: cancelLabel,
        background: AppColors.background,
        foreground: AppColors.textSub,
        onTap: () => Navigator.pop(context, false),
      ),
      _DialogButton(
        label: confirmLabel,
        background: destructive ? AppColors.danger : AppColors.primary,
        foreground: destructive ? Colors.white : AppColors.onPrimary,
        onTap: () => Navigator.pop(context, true),
      ),
    ],
  );
  return confirmed == true;
}

/// 알리기만 하는 대화상자. 버튼 하나.
Future<void> showNoticeDialog(
  BuildContext context, {
  String? title,
  required String body,
  String okLabel = '확인',
}) =>
    _show<void>(
      context,
      title: title,
      body: body,
      buttons: (context) => [
        _DialogButton(
          label: okLabel,
          background: AppColors.primary,
          foreground: AppColors.onPrimary,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );

Future<T?> _show<T>(
  BuildContext context, {
  required String? title,
  required String? body,
  required List<Widget> Function(BuildContext context) buttons,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => _DialogCard(
      title: title,
      body: body,
      buttons: buttons(context),
    ),
    // 살짝 커지며 나타난다.
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DialogCard extends StatelessWidget {
  const _DialogCard(
      {required this.title, required this.body, required this.buttons});

  final String? title;
  final String? body;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final width = math.min(340.0, MediaQuery.sizeOf(context).width - 48);
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(24, 26, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(title!,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: AppColors.text)),
                ),
              if (body != null) ...[
                if (title != null) const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(body!,
                      style: const TextStyle(
                          fontSize: 15, height: 1.5, color: AppColors.textSub)),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  for (final (i, b) in buttons.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: b),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: foreground)),
      ),
    );
  }
}
