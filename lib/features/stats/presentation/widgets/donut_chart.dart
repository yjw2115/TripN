import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';

/// [label]이 있으면 조각 바깥으로 선을 이어 이름을 적는다.
typedef DonutSlice = ({Color color, int value, String label});

/// 도넛 모양 원형 그래프. 12시 방향에서 시계 방향으로 [slices]를 차례로 그린다.
///
/// 처음 그릴 때(그리고 [animationKey]가 바뀔 때) 한 바퀴 펼쳐지고, 이름표는 조각이 그려지는 대로 나타난다.
/// 조각이나 이름표를 누르면 [onSelect]로 그 순서를, 가운데나 바깥을 누르면 null을 준다.
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

  /// 도넛 지름. 양옆에 이름표 자리가 모자라면 줄어든다.
  final double size;
  final double thickness;

  /// 고른 조각이 바깥으로 두꺼워질 만큼.
  static const _grow = 8.0;

  /// 이름표 선: 도넛 바깥에서 꺾이는 곳까지, 꺾인 뒤 가로선, 선 끝과 글자 사이.
  static const _elbow = 12.0, _tick = 10.0, _textGap = 4.0;

  static const _labelStyle = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSub);

  double _radius(double diameter) => (diameter - thickness - _grow * 2) / 2;

  _Layout _layout(BuildContext context, double maxWidth) {
    final total = slices.fold(0, (sum, s) => sum + s.value);
    final style = DefaultTextStyle.of(context).style.merge(_labelStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final sizes = <int, Size>{};
    for (final (i, s) in slices.indexed) {
      if (s.value <= 0 || s.label.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: s.label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      sizes[i] = painter.size;
      painter.dispose();
    }
    if (total <= 0 || sizes.isEmpty) {
      return _Layout(
          box: Size.square(size),
          center: Offset(size / 2, size / 2),
          diameter: size,
          labels: const []);
    }

    final textWidth = sizes.values.map((s) => s.width).reduce(max);
    final textHeight = sizes.values.map((s) => s.height).reduce(max);
    final side = _elbow + _tick + _textGap + textWidth;
    final width = min(maxWidth, size + side * 2);
    final diameter = max(size * 0.6, min(size, width - side * 2));
    final box = Size(width, diameter + (_elbow + textHeight / 2) * 2);
    final c = box.center(Offset.zero);
    final lineRadius = diameter / 2 + _elbow;

    final labels = <_Label>[];
    var start = 0.0;
    for (final (i, s) in slices.indexed) {
      if (s.value <= 0) continue;
      final sweep = s.value / total * 2 * pi;
      final mid = start + sweep / 2;
      start += sweep;
      final textSize = sizes[i];
      if (textSize == null) continue;
      labels.add(_Label(
        index: i,
        text: s.label,
        angle: mid,
        right: sin(mid) >= 0,
        size: textSize,
        y: c.dy - cos(mid) * lineRadius,
      ));
    }

    // 한쪽에 몰린 이름표는 위아래로 밀어 겹치지 않게 한다.
    final spacing = textHeight + 3;
    for (final right in [true, false]) {
      final group = labels.where((l) => l.right == right).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      for (final (i, l) in group.indexed) {
        final floor = i == 0 ? textHeight / 2 : group[i - 1].y + spacing;
        l.y = max(l.y, floor);
      }
      for (var i = group.length - 1; i >= 0; i--) {
        final ceiling = i == group.length - 1
            ? box.height - textHeight / 2
            : group[i + 1].y - spacing;
        group[i].y = min(group[i].y, ceiling);
      }
    }

    final radius = _radius(diameter);
    for (final l in labels) {
      final dir = l.right ? 1.0 : -1.0;
      final edge = l.index == selected
          ? radius + (thickness + _grow) / 2
          : radius + thickness / 2;
      l.anchor = c + Offset(sin(l.angle), -cos(l.angle)) * (edge + 3);
      final dy = l.y - c.dy;
      // 꺾이는 곳은 시작점보다 안쪽으로 들어가지 않게 해서 선이 도넛을 가로지르지 않는다.
      var x = c.dx + dir * sqrt(max(lineRadius * lineRadius - dy * dy, 0));
      x = l.right ? max(x, l.anchor.dx) : min(x, l.anchor.dx);
      l.elbow = Offset(x, l.y);
      l.end = Offset(x + dir * _tick, l.y);
      final left = l.right ? l.end.dx + _textGap : l.end.dx - _textGap - l.size.width;
      l.rect = Rect.fromLTWH(left, l.y - l.size.height / 2, l.size.width, l.size.height);
    }
    return _Layout(box: box, center: c, diameter: diameter, labels: labels);
  }

  int? _hit(_Layout layout, Offset position) {
    for (final l in layout.labels) {
      if (l.rect.inflate(8).contains(position)) return l.index;
    }
    return _sliceAt(position - layout.center, layout.diameter);
  }

  int? _sliceAt(Offset offset, double diameter) {
    final radius = _radius(diameter);
    final distance = offset.distance;
    if (distance < radius - thickness / 2 - 8 ||
        distance > radius + thickness / 2 + _grow + 8) {
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
    return LayoutBuilder(builder: (context, constraints) {
      final layout = _layout(context, constraints.maxWidth);
      final c = layout.center;
      final d = layout.diameter;
      final radius = _radius(d);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onSelect == null
            ? null
            : (details) => onSelect(_hit(layout, details.localPosition)),
        child: SizedBox.fromSize(
          size: layout.box,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(animationKey),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DonutPainter(
                      slices: slices,
                      labels: layout.labels,
                      selected: selected,
                      progress: progress,
                      center: c,
                      radius: radius,
                      thickness: thickness,
                      grow: _grow,
                    ),
                  ),
                ),
                child!,
                for (final l in layout.labels)
                  Positioned.fromRect(
                    rect: l.rect,
                    child: Opacity(
                      opacity: l.opacity(progress, selected),
                      child: Text(l.text,
                          maxLines: 1,
                          softWrap: false,
                          style: l.index == selected
                              ? _labelStyle.copyWith(color: AppColors.text)
                              : _labelStyle),
                    ),
                  ),
              ],
            ),
            child: Positioned(
              left: c.dx - d / 2,
              top: c.dy - d / 2,
              width: d,
              height: d,
              child: Center(
                child: SizedBox(
                  width: (radius - thickness / 2) * 2 - 16,
                  child: center,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 조각 하나의 이름표. 선은 [anchor] → [elbow] → [end]로 꺾이고, 글자는 [rect]에 놓인다.
class _Label {
  _Label({
    required this.index,
    required this.text,
    required this.angle,
    required this.right,
    required this.size,
    required this.y,
  });

  final int index;
  final String text;

  /// 조각 한가운데 각도. 12시가 0, 시계 방향.
  final double angle;
  final bool right;
  final Size size;
  double y;

  late final Offset anchor;
  late final Offset elbow;
  late final Offset end;
  late final Rect rect;

  /// 펼쳐지는 그래프가 조각 가운데를 지나면 나타난다. 12시 바로 앞 조각도 끝날 때는 다 보이도록
  /// 한 바퀴보다 조금 더 돈다고 친다. 다른 조각을 고르면 흐려진다.
  double opacity(double progress, int? selected) {
    const fade = 0.4;
    final shown = ((progress * (2 * pi + fade) - angle) / fade).clamp(0.0, 1.0);
    return selected != null && selected != index ? shown * 0.3 : shown;
  }
}

class _Layout {
  const _Layout(
      {required this.box,
      required this.center,
      required this.diameter,
      required this.labels});

  final Size box;
  final Offset center;
  final double diameter;
  final List<_Label> labels;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.labels,
    required this.selected,
    required this.progress,
    required this.center,
    required this.radius,
    required this.thickness,
    required this.grow,
  });

  final List<DonutSlice> slices;
  final List<_Label> labels;
  final int? selected;
  final double progress;
  final Offset center;
  final double radius;
  final double thickness;
  final double grow;

  /// 조각 사이를 띄우는 흰 틈 (px).
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
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

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    for (final l in labels) {
      final opacity = l.opacity(progress, selected);
      if (opacity <= 0) continue;
      line.color = slices[l.index].color.withValues(alpha: opacity);
      canvas.drawPath(
          Path()
            ..moveTo(l.anchor.dx, l.anchor.dy)
            ..lineTo(l.elbow.dx, l.elbow.dy)
            ..lineTo(l.end.dx, l.end.dy),
          line);
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.slices != slices ||
      old.labels != labels ||
      old.center != center ||
      old.radius != radius;
}
