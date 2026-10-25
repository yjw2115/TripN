import 'package:flutter/material.dart';

/// 딱지 앞면 종이 두 장의 색. 결과(초록·빨강)와 헷갈리지 않게 그 두 색은 쓰지 않는다.
class DdakjiPaper {
  const DdakjiPaper(this.a, this.b);

  final Color a;
  final Color b;
}

const ddakjiPapers = [
  DdakjiPaper(Color(0xFF6FAEEA), Color(0xFFC4E0FA)),
  DdakjiPaper(Color(0xFFFFC94A), Color(0xFFFFE8A6)),
  DdakjiPaper(Color(0xFFA996EE), Color(0xFFDCD2FA)),
  DdakjiPaper(Color(0xFFCDA574), Color(0xFFEBD8B8)),
];

/// 뒤집었을 때 나오는 면. 초록은 통과, 빨강은 당첨.
enum DdakjiBack { pass, hit }

/// 종이 딱지 한 장. 앞면은 두 색 날개가 엇갈린 바람개비 모양, 뒷면은 띠가 엇갈린 십자 모양이다.
class DdakjiPainter extends CustomPainter {
  const DdakjiPainter.front(DdakjiPaper this.paper) : back = null;

  const DdakjiPainter.back(DdakjiBack this.back) : paper = null;

  final DdakjiPaper? paper;
  final DdakjiBack? back;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final square = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: h * 2, height: h * 2),
      Radius.circular(h * 0.1),
    );
    canvas.save();
    canvas.clipRRect(square);
    final Color edge;
    if (paper case final paper?) {
      edge = _front(canvas, c, h, paper);
    } else {
      edge = _back(canvas, c, h, back!);
    }
    canvas.restore();
    canvas.drawRRect(
      square.deflate(h * 0.015),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.03
        ..color = edge,
    );
  }

  Color _front(Canvas canvas, Offset c, double h, DdakjiPaper paper) {
    final tl = c + Offset(-h, -h);
    final tr = c + Offset(h, -h);
    final br = c + Offset(h, h);
    final bl = c + Offset(-h, h);
    Path flap(Offset p1, Offset p2) => Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    final a = Paint()..color = paper.a;
    final b = Paint()..color = paper.b;
    canvas
      ..drawPath(flap(tl, tr), a)
      ..drawPath(flap(br, bl), a)
      ..drawPath(flap(bl, tl), b)
      ..drawPath(flap(tr, br), b);

    // 날개가 시계 방향으로 다음 날개를 덮는 그림자 (바람개비)
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.07);
    for (final (corner, along) in [(tr, br), (br, bl), (bl, tl), (tl, tr)]) {
      final tip = c + (along - c) * 0.12;
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(tip.dx, tip.dy)
          ..close(),
        shade,
      );
    }
    final crease = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = h * 0.025;
    canvas
      ..drawLine(tl, br, crease)
      ..drawLine(tr, bl, crease)
      ..drawCircle(
        c + Offset(-h * 0.45, -h * 0.62),
        h * 0.07,
        Paint()..color = Colors.white.withValues(alpha: 0.45),
      );
    return Color.lerp(paper.a, Colors.black, 0.18)!;
  }

  Color _back(Canvas canvas, Offset c, double h, DdakjiBack back) {
    final (base, light, dark) = switch (back) {
      DdakjiBack.pass => (
          const Color(0xFF4CB86A),
          const Color(0xFF8ED9A0),
          const Color(0xFF2F8A4A),
        ),
      DdakjiBack.hit => (
          const Color(0xFFEF4B4B),
          const Color(0xFFF89A96),
          const Color(0xFFB72C2C),
        ),
    };
    canvas.drawRect(
      Rect.fromCenter(center: c, width: h * 2, height: h * 2),
      Paint()..color = base,
    );
    final band = h * 0.36;
    final bands = Paint()..color = light;
    canvas
      ..drawRect(
          Rect.fromCenter(center: c, width: h * 2, height: band * 2), bands)
      ..drawRect(
          Rect.fromCenter(center: c, width: band * 2, height: h * 2), bands);
    final fold = Paint()
      ..color = dark.withValues(alpha: 0.25)
      ..strokeWidth = h * 0.025;
    for (final d in [-band, band]) {
      canvas
        ..drawLine(c + Offset(-h, d), c + Offset(h, d), fold)
        ..drawLine(c + Offset(d, -h), c + Offset(d, h), fold);
    }

    canvas.drawCircle(c, h * 0.42, Paint()..color = Colors.white);
    final mark = Paint()
      ..color = base
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (back) {
      case DdakjiBack.pass:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - h * 0.2, c.dy + h * 0.01)
            ..lineTo(c.dx - h * 0.05, c.dy + h * 0.16)
            ..lineTo(c.dx + h * 0.22, c.dy - h * 0.14),
          mark,
        );
      case DdakjiBack.hit:
        canvas
          ..drawLine(c + Offset(0, -h * 0.22), c + Offset(0, h * 0.04), mark)
          ..drawCircle(c + Offset(0, h * 0.2), h * 0.075,
              Paint()..color = base);
    }
    return dark;
  }

  @override
  bool shouldRepaint(DdakjiPainter old) =>
      old.paper != paper || old.back != back;
}
