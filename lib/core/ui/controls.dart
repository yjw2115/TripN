import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// 머티리얼 대신 쓰는 작은 컨트롤들: 스위치, 칩, 체크 줄, 로딩 표시.

/// 불러오는 중. 머티리얼 원형 진행 표시 대신 iOS식 바퀴.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.radius = 12, this.color});

  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      CupertinoActivityIndicator(radius: radius, color: color);
}

/// 제목·설명과 켜고 끄는 스위치가 있는 줄.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        titleStyle ??
                        const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppColors.primaryDeep,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// 고르는 칩. 고르면 연한 초록 바탕에 진한 초록 글자.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? iconColor;

  /// 아이콘 대신 앞에 둘 위젯 (동행자 아바타 등).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.fromLTRB(
          leading != null ? 6 : (icon == null ? 14 : 10),
          9,
          14,
          9,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primaryDeep : const Color(0x00000000),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? AppColors.textSub),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: !enabled
                    ? AppColors.textHint
                    : selected
                    ? AppColors.primaryDeep
                    : AppColors.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 둥근 체크 표시. 켜지면 진한 초록 원에 흰 체크.
class CheckMark extends StatelessWidget {
  const CheckMark({super.key, required this.checked, this.size = 24});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? AppColors.primaryDeep : Colors.transparent,
        border: Border.all(
          color: checked ? AppColors.primaryDeep : AppColors.border,
          width: 2,
        ),
      ),
      child: checked
          ? Icon(AppIcons.check, size: size * 0.6, color: Colors.white)
          : null,
    );
  }
}

/// 체크하고 끄는 줄 (함께 쓴 사람, 정산할 지출 고르기).
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.checked,
    required this.onChanged,
    this.titleStyle,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final bool checked;

  /// null이면 고를 수 없다 (흐리게 보인다).
  final ValueChanged<bool>? onChanged;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged(!checked),
      child: Opacity(
        opacity: onChanged == null ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style:
                          titleStyle ??
                          const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                      child: title,
                    ),
                    if (subtitle != null)
                      DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textHint,
                        ),
                        child: subtitle!,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CheckMark(checked: checked),
            ],
          ),
        ),
      ),
    );
  }
}
