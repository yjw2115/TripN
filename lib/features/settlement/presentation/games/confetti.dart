import 'dart:math';

import 'package:flutter/material.dart';

/// 걸린 사람이 정해지면 화면 가운데서 한 번 터지는 색종이.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

const _colors = [
  Color(0xFFB9E4A7),
  Color(0xFFFFD65A),
  Color(0xFFFF9B6A),
  Color(0xFFF7B2C4),
  Color(0xFFA8D8F0),
  Color(0xFFD4C4F5),
];

class _Piece {
  _Piece(Random r)
    : angle = -pi * (0.1 + r.nextDouble() * 0.8),
      speed = 0.7 + r.nextDouble() * 0.9,
      spin = (r.nextDouble() - 0.5) * 14,
      size = 5 + r.nextDouble() * 5,
      round = r.nextDouble() < 0.3,
      color = _colors[r.nextInt(_colors.length)];

  final double angle;
  final double speed;
  final double spin;
  final double size;
  final bool round;
  final Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();
  final _pieces = [for (var i = 0; i < 70; i++) _Piece(Random())];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(_c, _pieces),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress, this.pieces) : super(repaint: progress);

  final Animation<double> progress;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value * 2.2; // 초
    if (progress.value >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.38);
    final fade = (1 - max(0, progress.value - 0.65) / 0.35).clamp(0.0, 1.0);
    for (final p in pieces) {
      final v = p.speed * size.height * 0.9;
      final drag = 1 - exp(-t * 2.2);
      final x = origin.dx + cos(p.angle) * v * drag / 2.2;
      final y =
          origin.dy +
          sin(p.angle) * v * drag / 2.2 +
          0.5 * size.height * 0.35 * t * t;
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 1.6,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
