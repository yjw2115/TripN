import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../trip/domain/trip.dart';
import '../../../trip/presentation/widgets/trip_widgets.dart';
import 'ddakji_painter.dart';

/// 딱지 뒤집기: 딱지 하나의 뒷면만 빨간색이다. 차례대로 한 장씩 뒤집고, 빨간 딱지를 뒤집은 사람이 걸린다.
///
/// 빨간 딱지 자리는 처음에 정해 두고 바꾸지 않는다. 마지막 한 장까지 가면 그 딱지를 뒤집은 사람이 걸려서
/// 누군가는 반드시 걸린다. 첫 딱지를 뒤집기 전에는 딱지 수를 바꿀 수 있다.
class DdakjiGame extends StatefulWidget {
  const DdakjiGame({
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
  State<DdakjiGame> createState() => _DdakjiGameState();
}

const _counts = [9, 12, 15, 18];

class _Ddakji {
  const _Ddakji(this.paper, this.tilt);

  final DdakjiPaper paper;

  /// 바닥에 흩어 놓은 듯 살짝 비뚤어진 각도.
  final double tilt;
}

class _DdakjiGameState extends State<DdakjiGame>
    with SingleTickerProviderStateMixin {
  late final Random _random;
  late final AnimationController _idle;
  late final List<Member> _order;
  late int _count;
  late List<_Ddakji> _ddakjis;
  late int _red;
  final _flippedBy = <int, Member>{};
  int? _flipping;
  int _turn = 0;
  bool _caught = false;

  @override
  void initState() {
    super.initState();
    _random = widget.random ?? Random.secure();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _order = [...widget.players]..shuffle(_random);
    final n = widget.players.length;
    _deal(n <= 3 ? 12 : (n <= 6 ? 15 : 18));
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  void _deal(int count) {
    _count = count;
    _ddakjis = [
      for (var i = 0; i < count; i++)
        _Ddakji(
          ddakjiPapers[_random.nextInt(ddakjiPapers.length)],
          (_random.nextDouble() - 0.5) * 0.24,
        ),
    ];
    _red = _random.nextInt(count);
  }

  bool get _started => _flippedBy.isNotEmpty || _flipping != null;

  /// 딱지가 가장 크게 들어가는 열 수와 칸 크기. 세로로 긴 화면에서는 3열이 된다.
  (int, double) _grid(Size area) {
    var best = (4, 0.0);
    for (final columns in const [3, 4, 5]) {
      final rows = (_count / columns).ceil();
      final cell = min(area.width / columns, area.height / rows);
      if (cell > best.$2 + 0.5) best = (columns, cell);
    }
    return (best.$1, min(best.$2, 130));
  }

  Member get _current => _order[_turn];

  void _flip(int i) {
    if (_flipping != null || _caught || _flippedBy.containsKey(i)) return;
    HapticFeedback.selectionClick();
    setState(() => _flipping = i);
  }

  void _onFlipped(int i) {
    final who = _current;
    if (i == _red) {
      setState(() {
        _caught = true;
        _flippedBy[i] = who;
        _flipping = null;
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) widget.onLoser(who);
      });
      return;
    }
    setState(() {
      _flippedBy[i] = who;
      _flipping = null;
      _turn = (_turn + 1) % _order.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final left = _count - _flippedBy.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: _TurnHeader(
            current: _current,
            next: _order.length > 1
                ? _order[(_turn + 1) % _order.length]
                : null,
            left: left,
            caught: _caught,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: _started
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '딱지',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSub,
                        ),
                      ),
                      const SizedBox(width: 8),
                      for (final count in _counts)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text('$count'),
                            selected: _count == count,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _deal(count)),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1E9DC),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE2D5C0), width: 2),
              ),
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, box) {
                  final (columns, cell) = _grid(box.biggest);
                  return Center(
                    child: SizedBox(
                      width: columns * cell,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          for (var i = 0; i < _count; i++)
                            SizedBox.square(
                              dimension: cell,
                              child: _DdakjiView(
                                key: ValueKey('ddakji-$i'),
                                index: i,
                                ddakji: _ddakjis[i],
                                idle: _idle,
                                isRed: i == _red,
                                flipping: _flipping == i,
                                flippedBy: _flippedBy[i],
                                onTap: () => _flip(i),
                                onFlipped: () => _onFlipped(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TurnHeader extends StatelessWidget {
  const _TurnHeader({
    required this.current,
    required this.next,
    required this.left,
    required this.caught,
  });

  final Member current;
  final Member? next;
  final int left;
  final bool caught;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey('${current.id}-$caught'),
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: caught ? AppColors.danger : AppColors.primaryDeep,
                width: 2.5,
              ),
            ),
            child: MemberAvatar(current, size: 44),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caught ? '${current.name}님 빨간 딱지!' : '${current.name}님 차례',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: caught ? AppColors.danger : AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caught
                      ? '당첨이에요 😱'
                      : [
                          '딱지 한 장을 뒤집어요',
                          '남은 딱지 $left',
                          if (next != null && next!.id != current.id)
                            '다음 ${next!.name}',
                        ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 딱지 한 장. 누르면 튀어 올라 뒤집히고 바닥에 "팡" 떨어진다.
/// 초록이면 뒤집은 사람을 남기고 흐려지고, 빨강이면 흔들린다.
class _DdakjiView extends StatefulWidget {
  const _DdakjiView({
    super.key,
    required this.index,
    required this.ddakji,
    required this.idle,
    required this.isRed,
    required this.flipping,
    required this.flippedBy,
    required this.onTap,
    required this.onFlipped,
  });

  final int index;
  final _Ddakji ddakji;
  final Animation<double> idle;
  final bool isRed;
  final bool flipping;
  final Member? flippedBy;
  final VoidCallback onTap;
  final VoidCallback onFlipped;

  @override
  State<_DdakjiView> createState() => _DdakjiViewState();
}

class _DdakjiViewState extends State<_DdakjiView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this);
  bool _pressed = false;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    // 이미 뒤집은 딱지는 다시 그려도 뒤집힌 채로 둔다.
    if (widget.flippedBy != null) _flip.value = 1;
  }

  @override
  void didUpdateWidget(_DdakjiView old) {
    super.didUpdateWidget(old);
    if (widget.flipping && !old.flipping) _start();
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _flip.duration = Duration(milliseconds: widget.isRed ? 1500 : 1100);
    _landed = false;
    await _flip.forward(from: 0);
    if (mounted) widget.onFlipped();
  }

  static double _seg(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final done = widget.flippedBy != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: done ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: done ? null : widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        child: LayoutBuilder(
          builder: (context, box) {
            final cell = box.maxWidth;
            final card = cell * 0.7;
            return AnimatedBuilder(
              animation: Listenable.merge([_flip, widget.idle]),
              builder: (context, _) {
                final active = widget.flipping || done;
                final t = active ? _flip.value : 0.0;
                final turn = Curves.easeInOut.transform(_seg(t, 0.05, 0.55));
                final lift = sin(turn * pi);
                final land = _seg(t, 0.55, 0.75);
                final squash = 1 - 0.12 * sin(land * pi);
                if (land > 0 && !_landed) {
                  _landed = true;
                  widget.isRed
                      ? HapticFeedback.heavyImpact()
                      : HapticFeedback.lightImpact();
                }
                final s = _seg(t, 0.6, 0.95);
                final shake = widget.isRed && s > 0 && s < 1
                    ? sin(s * pi * 14) * 5 * (1 - s)
                    : 0.0;
                final heat = widget.isRed ? _seg(t, 0.55, 0.75) : 0.0;
                final dim = widget.isRed ? 0.0 : _seg(t, 0.8, 1) * 0.45;
                final tilt = widget.ddakji.tilt +
                    (active
                        ? 0.0
                        : sin(widget.idle.value * 2 * pi + widget.index * 0.9) *
                            0.03);
                final showBack = turn >= 0.5;
                final cheer = _seg(t, 0.55, 0.95);
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // 바닥 그림자: 딱지가 뜨면 작고 흐려진다.
                    Transform.rotate(
                      angle: tilt,
                      child: Container(
                        width: card * (1 - lift * 0.2),
                        height: card * (1 - lift * 0.2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(card * 0.1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: 0.16 * (1 - lift * 0.5),
                              ),
                              blurRadius: 3 + lift * 10,
                              offset: Offset(0, 3 + lift * 12),
                            ),
                            if (heat > 0)
                              BoxShadow(
                                color: AppColors.danger.withValues(
                                  alpha: 0.55 * heat,
                                ),
                                blurRadius: 18,
                                spreadRadius: 4,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (land > 0 && land < 1)
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size.square(cell),
                          painter: _ImpactPainter(land, card),
                        ),
                      ),
                    Opacity(
                      opacity: 1 - dim,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..translateByDouble(shake, -lift * cell * 0.2, 0, 1)
                          ..rotateZ(tilt)
                          ..scaleByDouble(
                            1 + lift * 0.2,
                            (1 + lift * 0.2) * squash,
                            1,
                            1,
                          )
                          ..setEntry(3, 2, 0.0015)
                          ..rotateX(showBack ? turn * pi - pi : turn * pi),
                        child: CustomPaint(
                          size: Size.square(card),
                          painter: showBack
                              ? DdakjiPainter.back(
                                  widget.isRed
                                      ? DdakjiBack.hit
                                      : DdakjiBack.pass,
                                )
                              : DdakjiPainter.front(widget.ddakji.paper),
                        ),
                      ),
                    ),
                    if (done && !widget.isRed)
                      Positioned(
                        right: cell * 0.06,
                        bottom: cell * 0.06,
                        child: Opacity(
                          opacity: _seg(t, 0.8, 1),
                          child: MemberAvatar(
                            widget.flippedBy!,
                            size: cell * 0.3,
                          ),
                        ),
                      ),
                    if (cheer > 0 && cheer < 1)
                      Positioned(
                        top: -4 - cheer * 18,
                        child: Opacity(
                          opacity: sin(cheer * pi),
                          child: Text(
                            widget.isRed ? '당첨!' : '통과!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: widget.isRed
                                  ? AppColors.danger
                                  : AppColors.primaryDeep,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 딱지가 떨어질 때 네 귀퉁이로 퍼지는 "팡" 선.
class _ImpactPainter extends CustomPainter {
  _ImpactPainter(this.progress, this.card);

  final double progress;
  final double card;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = const Color(0xFF8A7A62).withValues(alpha: 1 - progress)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final from = card * (0.62 + progress * 0.12);
    final to = from + card * 0.14;
    for (var k = 0; k < 4; k++) {
      final a = pi / 4 + k * pi / 2;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(c + d * from, c + d * to, paint);
    }
  }

  @override
  bool shouldRepaint(_ImpactPainter old) => old.progress != progress;
}
