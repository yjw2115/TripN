import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/trip.dart';

/// 이름 첫 글자를 넣은 동그라미. 앱을 쓰는 동행자는 초록, 이름만 있는 동행자는 회색.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.size = 40});

  final Member member;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: member.isGuest ? AppColors.background : AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: Text(
        member.initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: member.isGuest ? AppColors.textSub : AppColors.primaryDeep,
        ),
      ),
    );
  }
}

/// 흰 바탕 둥근 카드. 제목 줄 오른쪽에 버튼을 둘 수 있다.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.children});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Text(title!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// Firestore 쓰기는 기기에 먼저 반영되니 기다리지 않는다 (오프라인이면 서버 응답이 한참 늦다).
/// 서버가 거절했을 때만 알려준다.
void reportWriteErrors(BuildContext context, Future<void> write) {
  final messenger = ScaffoldMessenger.of(context);
  unawaited(write.catchError((Object e) {
    debugPrint('Write failed: $e');
    messenger.showSnackBar(
        const SnackBar(content: Text('저장하지 못했어요. 잠시 후 다시 시도해 주세요.')));
  }));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소')),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: AppColors.danger)
                : null,
            child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed == true;
}
