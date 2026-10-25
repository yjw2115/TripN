import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../trip/domain/trip.dart';

/// 룰렛: 한 사람에 한 칸씩 나눈 돌림판을 돌리고, 바늘이 멈춘 칸의 사람이 걸린다.
///
/// 돌리기 전에 걸릴 사람을 모두 같은 확률로 뽑아 두고, 그 칸 안의 아무 자리에서 멈추도록 여러 바퀴
/// 돌린다. 칸 경계를 지날 때마다 바늘이 튕기고 점점 느려진다.
class RouletteGame extends StatefulWidget {
  const RouletteGame({
    super.key,
    required this.players,
    required this.onLoser,
    this.random,
  });

  final List<Member> players;
  final ValueChanged<Member> onLoser;

  /// 테스트에서 고정한다. 없으면 [Random.secure].
  final Random? random;

  @override
  State<RouletteGame> createState() => _RouletteGameState();
}

/// 칸 색. 검은 이름이 잘 보이는 밝은 색만 쓰고, 이웃한 칸끼리 겹치지 않게 돌려 쓴다.
const _colors = [
  Color(0xFFFF9E9E), // 산호
  Color(0xFFFFC978), // 귤
  Color(0xFFFFE47A), // 레몬
  Color(0xFFA8E6A1), // 연두
  Color(0xFF94CEFF), // 하늘
  Color(0xFFC9B6FF), // 라벤더
  Color(0xFFFFB5D3), // 분홍
  Color(0xFF8FE5D8), // 민트
];

/// [index]번 칸 색. 마지막 칸이 첫 칸과 같은 색이 되면 가운데 색으로 바꾼다.
Color rouletteColor(int index, int count) {
  final n = _colors.length;
  if (count > 1 && index == count - 1 && (count - 1) % n == 0) {
    return _colors[n ~/ 2];
  }
  return _colors[index % n];
}

/// 바늘(12시) 아래에 있는 칸. 칸 0은 12시에서 시계 방향으로 시작하고, 돌림판은 시계 방향으로
/// [rotation]만큼 돌았다.
int rouletteSegmentAt(double rotation, int count) {
  final slice = 2 * pi / count;
  return ((-rotation) % (2 * pi) / slice).floor() % count;
}

/// [from]에서 시계 방향으로 [spins]바퀴 넘게 돌아, [index]번 칸의 [within](0~1) 자리가 바늘 아래에
/// 오는 각도.
double rouletteStop({
  required double from,
  required int index,
  required int count,
  required int spins,
  required double within,
}) {
  final slice = 2 * pi / count;
  final target = (-(index + within) * slice) % (2 * pi);
  return from + spins * 2 * pi + (target - from) % (2 * pi);
}

enum _Phase { ready, spinning, stopped }

class _RouletteGameState extends State<RouletteGame>
    with TickerProviderStateMixin {
  late final Random _random = widget.random ?? Random.secure();
  late final AnimationController _spin = AnimationController(vsync: this)
    ..addListener(_onSpin);

  /// 테두리 전구 깜빡임과 걸린 칸 강조.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  /// 칸 경계를 지날 때 바늘이 튕기는 움직임.
  late final AnimationController _flick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  /// 처음 모양도 매번 다르게 돌려 둔다.
  late final double _from = _random.nextDouble() * 2 * pi;
  late double _to = _from;
  int? _segment;
  int? _loser;
  _Phase _phase = _Phase.ready;

  int get _count => widget.players.length;

  double get _rotation =>
      _from + (_to - _from) * Curves.easeOutQuart.transform(_spin.value);

  @override
  void dispose() {
    _spin.dispose();
    _glow.dispose();
    _flick.dispose();
    super.dispose();
  }

  void _start() {
    if (_phase != _Phase.ready) return;
    final loser = _random.nextInt(_count);
    _to = rouletteStop(
      from: _from,
      index: loser,
      count: _count,
      spins: 5 + _random.nextInt(3),
      within: 0.15 + _random.nextDouble() * 0.7,
    );
    _spin.duration = Duration(milliseconds: 4200 + _random.nextInt(1200));
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.spinning;
      _loser = loser;
    });
    _spin.forward(from: 0).then((_) => _stopped());
  }

  void _onSpin() {
    final segment = rouletteSegmentAt(_rotation, _count);
    if (segment == _segment) return;
    _segment = segment;
    HapticFeedback.selectionClick();
    _flick.forward(from: 0);
  }

  void _stopped() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _phase = _Phase.stopped);
    final loser = widget.players[_loser!];
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) widget.onLoser(loser);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loser = _phase == _Phase.stopped ? widget.players[_loser!] : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (_phase) {
                    _Phase.ready => '누가 걸릴까요?',
                    _Phase.spinning => '두구두구…',
                    _Phase.stopped => '${loser!.name}님!',
                  },
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '바늘이 멈춘 칸의 사람이 걸려요',
                  style: TextStyle(fontSize: 14, color: AppColors.textSub),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, box) {
                final size = min(box.maxWidth, box.maxHeight);
                return Center(
                  child: SizedBox.square(
                    dimension: size,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_spin, _glow, _flick]),
                      builder: (context, _) => _Wheel(
                        names: [for (final p in widget.players) p.name],
                        rotation: _rotation,
                        glow: _glow.value,
                        flick: _flick.isAnimating ? 1 - _flick.value : 0,
                        loser: _phase == _Phase.stopped ? _loser : null,
                        onHub: _phase == _Phase.ready ? _start : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton(
              onPressed: _phase == _Phase.ready ? _start : null,
              child: Text(switch (_phase) {
                _Phase.ready => '돌리기!',
                _Phase.spinning => '돌아가는 중…',
                _Phase.stopped => '멈췄어요',
              }),
            ),
          ),
        ),
      ],
    );
  }
}

/// 돌림판, 테두리 전구, 12시 바늘, 가운데 버튼.
class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.names,
    required this.rotation,
    required this.glow,
    required this.flick,
    required this.loser,
    required this.onHub,
  });

  final List<String> names;
  final double rotation;
  final double glow;

  /// 바늘이 튕긴 정도 (1이면 막 튕김).
  final double flick;
  final int? loser;
  final VoidCallback? onHub;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.maxWidth;
        final hub = size * 0.22;
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: RouletteRimPainter(glow: glow),
            ),
            Transform.rotate(
              angle: rotation,
              child: CustomPaint(
                size: Size.square(size),
                painter: RouletteWheelPainter(
                  count: names.length,
                  names: names,
                  highlight: loser,
                  pulse: glow,
                ),
              ),
            ),
            GestureDetector(
              onTap: onHub,
              child: Container(
                width: hub,
                height: hub,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2B2D42), width: 4),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 8),
                  ],
                ),
                child: Text(
                  onHub != null ? '돌려!' : '🎯',
                  style: TextStyle(
                    fontSize: hub * 0.26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Transform.rotate(
                angle: -0.35 * flick,
                alignment: Alignment.topCenter,
                child: CustomPaint(
                  size: Size(size * 0.12, size * 0.14),
                  painter: const RoulettePointerPainter(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 칸을 나눈 돌림판. [names]가 비어 있으면 이름 없이 칸만 그린다 (게임 아이콘).
class RouletteWheelPainter extends CustomPainter {
  const RouletteWheelPainter({
    required this.count,
    this.names = const [],
    this.highlight,
    this.pulse = 0,
  });

  final int count;
  final List<String> names;

  /// 걸린 칸. 있으면 다른 칸은 흐리게 그린다.
  final int? highlight;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 * 0.86;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final slice = 2 * pi / count;
    for (var i = 0; i < count; i++) {
      var color = rouletteColor(i, count);
      if (highlight != null && highlight != i) {
        color = Color.lerp(color, Colors.white, 0.6)!;
      } else if (highlight == i) {
        color = Color.lerp(color, Colors.white, 0.15 * pulse)!;
      }
      // 가운데는 밝고 바깥은 진하게 해서 판에 깊이를 준다.
      canvas.drawArc(
        rect,
        -pi / 2 + i * slice,
        slice,
        true,
        Paint()
          ..shader = ui.Gradient.radial(center, radius,
              [Color.lerp(color, Colors.white, 0.25)!, color], [0.2, 1]),
      );
    }
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = max(1, size.width * 0.008);
    for (var i = 0; i < count; i++) {
      final a = -pi / 2 + i * slice;
      canvas.drawLine(
          center, center + Offset(cos(a), sin(a)) * radius, line);
    }
    if (highlight case final i?) {
      canvas.drawArc(
        rect.deflate(size.width * 0.012),
        -pi / 2 + i * slice,
        slice,
        true,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6 + 0.4 * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (0.012 + 0.008 * pulse)
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (names.isEmpty) return;

    // 이름은 칸의 한가운데(가운데 버튼과 테두리 사이)에 둔다. 칸이 넓으면 가로로 써서 바늘 아래에
    // 왔을 때 똑바로 읽히고, 좁으면 반지름을 따라 쓴다.
    final mid = radius * 0.63;
    final band = radius * 0.62;
    final fontSize = radius * (count <= 3 ? 0.15 : (count <= 6 ? 0.13 : 0.11));
    for (var i = 0; i < count; i++) {
      final faded = highlight != null && highlight != i;
      TextPainter label(double maxWidth, double fontSize) => TextPainter(
            text: TextSpan(
              text: names[i],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: faded ? AppColors.textHint : AppColors.text,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: maxWidth);
      final across = mid * slice * 0.78;
      final a = -pi / 2 + (i + 0.5) * slice;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      var painter = label(double.infinity, fontSize);
      if (painter.width <= across && painter.height <= band) {
        canvas.rotate(a + pi / 2);
        painter.paint(
            canvas, Offset(-painter.width / 2, -mid - painter.height / 2));
      } else {
        painter = label(band, min(fontSize, mid * slice * 0.5));
        canvas.rotate(a);
        painter.paint(
            canvas, Offset(mid - painter.width / 2, -painter.height / 2));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(RouletteWheelPainter old) =>
      old.count != count ||
      old.highlight != highlight ||
      old.pulse != pulse ||
      old.names.join() != names.join();
}

/// 돌림판 바깥 테두리와 깜빡이는 전구. 돌지 않는다.
class RouletteRimPainter extends CustomPainter {
  const RouletteRimPainter({required this.glow, this.bulbs = 16});

  final double glow;
  final int bulbs;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius * 0.98,
        Paint()..color = const Color(0xFF2B2D42));
    final lit = glow > 0.5 ? 0 : 1;
    for (var i = 0; i < bulbs; i++) {
      final a = -pi / 2 + i * 2 * pi / bulbs;
      final on = i % 2 == lit;
      canvas.drawCircle(
        center + Offset(cos(a), sin(a)) * radius * 0.92,
        radius * 0.032,
        Paint()..color = on ? const Color(0xFFFFF3B0) : const Color(0xFF8D7A3A),
      );
    }
  }

  @override
  bool shouldRepaint(RouletteRimPainter old) =>
      (old.glow > 0.5) != (glow > 0.5) || old.bulbs != bulbs;
}

/// 12시에서 아래를 가리키는 빨간 바늘.
class RoulettePointerPainter extends CustomPainter {
  const RoulettePointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFFF04452));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.5, size.width * 0.08)
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(RoulettePointerPainter old) => false;
}
