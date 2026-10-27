import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';

typedef DonutSlice = ({Color color, int value});

/// 도넛 모양 원형 그래프. 12시 방향에서 시계 방향으로 [slices]를 차례로 그린다.
///
/// 처음 그릴 때(그리고 [animationKey]가 바뀔 때) 한 바퀴 펼쳐진다.
/// 조각을 누르면 [onSelect]로 그 순서를, 가운데나 바깥을 누르면 null을 준다.
/// 고른 조각은 두꺼워지고 나머지는 흐려진다.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.center,
    this.selected,
    this.onSelect,
    this.animationKey,
    this.size = 216,
    this.thickness = 30,
  });

  final List<DonutSlice> slices;
  final Widget center;
  final int? selected;
  final ValueChanged<int?>? onSelect;
  final Object? animationKey;
  final double size;
  final double thickness;

  /// 고른 조각이 바깥으로 두꺼워질 만큼.
  static const _grow = 8.0;

  double get _radius => (size - thickness - _grow * 2) / 2;

  int? _sliceAt(Offset position) {
    final offset = position - Offset(size / 2, size / 2);
    final distance = offset.distance;
    if (distance < _radius - thickness / 2 - 8 ||
        distance > _radius + thickness / 2 + _grow + 8) {
      return null;
    }
    // 12시 방향이 0, 시계 방향으로 늘어난다.
    final angle = (atan2(offset.dy, offset.dx) + pi / 2) % (2 * pi);
    final total = slices.fold(0, (sum, s) => sum + s.value);
    if (total <= 0) return null;
    var start = 0.0;
    for (final (i, s) in slices.indexed) {
      final end = start + s.value / total * 2 * pi;
      if (angle < end) return i;
      start = end;
    }
    return slices.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final onSelect = this.onSelect;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onSelect == null
          ? null
          : (details) => onSelect(_sliceAt(details.localPosition)),
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(animationKey),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          builder: (context, progress, child) => CustomPaint(
            painter: _DonutPainter(
              slices: slices,
              selected: selected,
              progress: progress,
              radius: _radius,
              thickness: thickness,
              grow: _grow,
            ),
            child: child,
          ),
          child: Center(
            child: SizedBox(
              width: (_radius - thickness / 2) * 2 - 16,
              child: center,
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.selected,
    required this.progress,
    required this.radius,
    required this.thickness,
    required this.grow,
  });

  final List<DonutSlice> slices;
  final int? selected;
  final double progress;
  final double radius;
  final double thickness;
  final double grow;

  /// 조각 사이를 띄우는 흰 틈 (px).
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final total = slices.fold(0, (sum, s) => sum + s.value);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      canvas.drawCircle(
          center,
          radius,
          paint
            ..strokeWidth = thickness
            ..color = AppColors.background);
      return;
    }
    final shown = slices.where((s) => s.value > 0).length;
    final gap = shown > 1 ? _gap / radius : 0.0;
    final end = progress * 2 * pi;
    var start = 0.0;
    for (final (i, s) in slices.indexed) {
      if (s.value <= 0) continue;
      final sweep = s.value / total * 2 * pi;
      final from = start;
      start += sweep;
      if (from >= end) break;
      final to = min(from + sweep, end);
      final arc = to - from - gap;
      if (arc <= 0) continue;
      final isSelected = i == selected;
      final dimmed = selected != null && !isSelected;
      // 고른 조각은 안쪽 가장자리를 그대로 두고 바깥으로만 두꺼워진다.
      final width = isSelected ? thickness + grow : thickness;
      final r = isSelected ? radius + grow / 2 : radius;
      paint
        ..strokeWidth = width
        ..color = dimmed ? s.color.withValues(alpha: 0.3) : s.color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r),
          -pi / 2 + from + gap / 2, arc, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.slices != slices ||
      old.radius != radius;
}
