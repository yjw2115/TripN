import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../trip/domain/trip.dart';

/// 파도타기: 한 사람이 물고기 한 마리씩 맡아 파도를 타고, 가장 늦게 도착한 사람이 걸린다.
///
/// 출발할 때 경주 전체를 미리 계산해 두고 그대로 보여준다. 물고기마다 속도가 수시로 바뀌고,
/// 가끔 졸거나(💤) 큰 파도를 탄다(🌊). 뒤처질수록 조금 빨라져서 끝까지 엎치락뒤치락한다.
class WaveRaceGame extends StatefulWidget {
  const WaveRaceGame({
    super.key,
    required this.players,
    required this.onFinish,
    this.random,
  });

  final List<Member> players;

  /// 들어온 순서. 마지막 사람이 걸린 사람이다.
  final ValueChanged<List<Member>> onFinish;

  /// 테스트에서 고정한다. 없으면 [Random.secure].
  final Random? random;

  @override
  State<WaveRaceGame> createState() => _WaveRaceGameState();
}

/// 애플·구글 이모지 모두 왼쪽을 보는 바다 친구들. 뒤집어서 오른쪽으로 헤엄치게 한다.
const _fish = [
  '🐟', '🐠', '🐡', '🦈', '🐬', '🐳', //
  '🐋', '🦭', '🐙', '🦑', '🦐', '🦀',
];

enum _Phase { ready, countdown, running, finished }

/// 헤엄치는 상태. 졸면 멈추고, 큰 파도를 타면 빨라진다.
enum _Stride { run, nap, dash }

/// 미리 계산한 경주. 1/60초마다 각자 어디까지 왔는지 적어 둔다.
class _Race {
  _Race._(this.progress, this.strides, this.finishTimes);

  static const fps = 60;

  /// [runner][frame] → 0~1
  final List<List<double>> progress;
  final List<List<_Stride>> strides;

  /// 결승선을 넘은 시각(초). 같은 프레임에 들어와도 넘은 순간으로 순위를 가린다.
  final List<double> finishTimes;

  int get frames => progress.first.length;

  /// 들어온 순서대로 달린 사람 번호.
  List<int> get order =>
      [for (var i = 0; i < finishTimes.length; i++) i]
        ..sort((a, b) => finishTimes[a].compareTo(finishTimes[b]));

  factory _Race.simulate(int runners, Random random) {
    const dt = 1 / fps;
    const base = 1 / 7; // 평균 7초쯤에 들어온다.
    final pos = List.filled(runners, 0.0);
    final factor = List.filled(runners, 1.0);
    final left = List.filled(runners, 0.0);
    final stride = List.filled(runners, _Stride.run);
    final finish = List.filled(runners, double.infinity);
    final progress = [for (var i = 0; i < runners; i++) <double>[]];
    final strides = [for (var i = 0; i < runners; i++) <_Stride>[]];

    double between(double a, double b) => a + random.nextDouble() * (b - a);
    void segment(int i, _Stride s, double f, double seconds) {
      stride[i] = s;
      factor[i] = f;
      left[i] = seconds;
    }

    for (var frame = 0; frame < fps * 40; frame++) {
      final leader = pos.reduce(max);
      for (var i = 0; i < runners; i++) {
        if (pos[i] < 1) {
          left[i] -= dt;
          if (left[i] <= 0) {
            final roll = random.nextDouble();
            if (roll < 0.07 && pos[i] > 0.15 && pos[i] < 0.85) {
              segment(i, _Stride.nap, 0, between(0.5, 1.1));
            } else if (roll < 0.17) {
              segment(i, _Stride.dash, between(1.9, 2.4), between(0.35, 0.6));
            } else {
              segment(i, _Stride.run, between(0.55, 1.45), between(0.3, 0.8));
            }
          }
          final catchUp = stride[i] == _Stride.run
              ? 1 + (leader - pos[i]) * 2.4
              : 1.0;
          final step = base * factor[i] * catchUp * dt;
          if (pos[i] + step >= 1) {
            finish[i] = (frame + (1 - pos[i]) / step) * dt;
            pos[i] = 1;
          } else {
            pos[i] += step;
          }
        }
        progress[i].add(pos[i]);
        strides[i].add(pos[i] >= 1 ? _Stride.run : stride[i]);
      }
      if (pos.every((p) => p >= 1)) break;
    }
    // 아주 드물게 시간 안에 못 들어오면 남은 거리 순으로 줄 세운다.
    for (var i = 0; i < runners; i++) {
      if (finish[i].isInfinite) finish[i] = 1000 - pos[i];
    }
    return _Race._(progress, strides, finish);
  }
}

class _WaveRaceGameState extends State<WaveRaceGame> with TickerProviderStateMixin {
  late final Random _random = widget.random ?? Random.secure();
  late final List<String> _emoji = () {
    final pool = [..._fish]..shuffle(_random);
    return [
      for (var i = 0; i < widget.players.length; i++) pool[i % pool.length],
    ];
  }();
  late final AnimationController _countdown;
  late final Ticker _ticker;
  _Phase _phase = _Phase.ready;
  _Race? _race;
  int _frame = 0;
  int _lastCount = 0;
  final _ranks = <int, int>{};

  @override
  void initState() {
    super.initState();
    _countdown =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 2700),
          )
          ..addListener(_onCountdown)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _go();
          });
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countdown.dispose();
    super.dispose();
  }

  void _start() {
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.countdown;
      _race = _Race.simulate(widget.players.length, _random);
      _lastCount = 3;
    });
    _countdown.forward(from: 0);
  }

  void _onCountdown() {
    final count = 3 - (_countdown.value * 3).floor();
    if (count != _lastCount && count > 0) {
      _lastCount = count;
      HapticFeedback.selectionClick();
    }
    setState(() {});
  }

  void _go() {
    HapticFeedback.heavyImpact();
    setState(() => _phase = _Phase.running);
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final race = _race!;
    final frame = elapsed.inMicroseconds * _Race.fps ~/ 1000000;
    final arrived = [
      for (var i = 0; i < widget.players.length; i++)
        if (!_ranks.containsKey(i) && race.finishTimes[i] * _Race.fps <= frame)
          i,
    ]..sort((a, b) => race.finishTimes[a].compareTo(race.finishTimes[b]));
    for (final i in arrived) {
      _ranks[i] = _ranks.length + 1;
    }
    if (arrived.isNotEmpty) HapticFeedback.lightImpact();
    setState(() => _frame = min(frame, race.frames - 1));
    if (frame >= race.frames + _Race.fps ~/ 2) {
      _ticker.stop();
      setState(() => _phase = _Phase.finished);
      final order = race.order;
      // 시간 안에 못 들어온 물고기까지 순위를 채운다.
      for (var r = 0; r < order.length; r++) {
        _ranks[order[r]] = r + 1;
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          widget.onFinish([for (final i in order) widget.players[i]]);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (_phase) {
                        _Phase.ready => '누가 늦게 도착할까요?',
                        _Phase.countdown => '준비…',
                        _Phase.running => '파도를 타요!',
                        _Phase.finished => '도착!',
                      },
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '가장 늦게 도착한 물고기가 걸려요',
                      style: TextStyle(fontSize: 14, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _Track(
                    players: widget.players,
                    emoji: _emoji,
                    race: _race,
                    frame: _phase == _Phase.ready || _phase == _Phase.countdown
                        ? null
                        : _frame,
                    ranks: _ranks,
                    loser: _phase == _Phase.finished ? _race!.order.last : null,
                  ),
                ),
                if (_phase == _Phase.countdown)
                  Positioned.fill(
                    child: _CountdownOverlay(progress: _countdown.value),
                  ),
              ],
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
                _Phase.ready => '출발!',
                _Phase.countdown || _Phase.running => '파도 타는 중…',
                _Phase.finished => '도착했어요',
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.progress});

  /// 0~1. 3 → 2 → 1 이 같은 길이로 지나간다.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final step = progress * 3;
    final count = 3 - step.floor().clamp(0, 2);
    final within = step - step.floor();
    final scale =
        1.6 - Curves.easeOutBack.transform(min(within * 2.5, 1)) * 0.6;
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.white.withValues(alpha: 0.35),
        child: Center(
          child: Opacity(
            opacity: (1 - max(0, within - 0.7) / 0.3).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 120,
                height: 120,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x22000000), blurRadius: 24),
                  ],
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDeep,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 바다 레인. 왼쪽에 이름, 오른쪽 끝에 부표 결승선. 파도는 경주하는 동안 흘러간다.
class _Track extends StatelessWidget {
  const _Track({
    required this.players,
    required this.emoji,
    required this.race,
    required this.frame,
    required this.ranks,
    required this.loser,
  });

  final List<Member> players;
  final List<String> emoji;
  final _Race? race;

  /// 출발 전에는 null.
  final int? frame;
  final Map<int, int> ranks;
  final int? loser;

  static const _nameWidth = 58.0;
  static const _finishInset = 40.0;

  /// 파도가 흘러간 정도. 출발 전에는 멈춰 있다.
  double get _phase => (frame ?? 0) * 0.09;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFCDEBFA),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFA8D8F2), width: 2),
      ),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, box) {
          final n = players.length;
          final lane = min(96.0, box.maxHeight / n);
          final size = (lane * 0.55).clamp(20.0, 50.0);
          final top = (box.maxHeight - lane * n) / 2;
          final startX = _nameWidth + size;
          final finishX = box.maxWidth - _finishInset;
          final f = frame;
          final leader = f == null || race == null
              ? null
              : [for (var i = 0; i < n; i++) i].reduce(
                  (a, b) =>
                      race!.progress[a][f] >= race!.progress[b][f] ? a : b,
                );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TrackPainter(
                    lanes: n,
                    laneHeight: lane,
                    top: top,
                    startX: startX,
                    finishX: finishX,
                    nameWidth: _nameWidth,
                    loserLane: loser,
                    phase: _phase,
                    amplitude: lane * 0.1,
                    fishSize: size,
                  ),
                ),
              ),
              for (var i = 0; i < n; i++) ...[
                Positioned(
                  left: 6,
                  top: top + lane * i,
                  width: _nameWidth - 8,
                  height: lane,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      players[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: lane < 36 ? 12 : 14,
                        fontWeight: FontWeight.w700,
                        color: loser == i ? AppColors.danger : _deepSea,
                      ),
                    ),
                  ),
                ),
                _runner(i, lane, size, top, startX, finishX, leader == i),
                if (ranks[i] case final rank?)
                  Positioned(
                    left: finishX + 15,
                    top: top + lane * i + (lane - 22) / 2,
                    child: _RankBadge(rank: rank, last: loser == i),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _runner(
    int i,
    double lane,
    double size,
    double top,
    double startX,
    double finishX,
    bool leading,
  ) {
    final f = frame;
    final p = f == null || race == null ? 0.0 : race!.progress[i][f];
    final stride = f == null || race == null
        ? _Stride.run
        : race!.strides[i][f];
    final x = startX + p * (finishX - startX) - size;
    // 물고기 몸 가운데가 파도 위에 올라탄다. 기울기만큼 몸을 기울인다.
    final (rise, slope) = _wave(x + size / 2, lane * 0.1, _phase);
    return Positioned(
      left: x,
      top: top + lane * i + (lane - size) / 2 + rise,
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(
            angle: atan(slope) * 0.9,
            child: Transform.flip(
              flipX: true,
              child: FittedBox(
                child: Text(emoji[i], style: const TextStyle(fontSize: 40)),
              ),
            ),
          ),
          if (stride == _Stride.nap && f != null)
            Positioned(
              right: -size * 0.35,
              top: -size * 0.35 + sin(f * 0.15) * 2,
              child: Text('💤', style: TextStyle(fontSize: size * 0.45)),
            ),
          if (stride == _Stride.dash && f != null)
            Positioned(
              left: -size * 0.55,
              top: size * 0.3,
              child: Text('🌊', style: TextStyle(fontSize: size * 0.45)),
            ),
          if (leading && p < 1)
            Positioned(
              left: size * 0.25,
              top: -size * 0.45,
              child: Text('👑', style: TextStyle(fontSize: size * 0.4)),
            ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.last});

  final int rank;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: last
              ? AppColors.danger
              : rank == 1
              ? const Color(0xFFFFC94A)
              : AppColors.surface,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$rank',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: last ? Colors.white : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.lanes,
    required this.laneHeight,
    required this.top,
    required this.startX,
    required this.finishX,
    required this.nameWidth,
    required this.loserLane,
    required this.phase,
    required this.amplitude,
    required this.fishSize,
  });

  final int lanes;
  final double laneHeight;
  final double top;
  final double startX;
  final double finishX;
  final double nameWidth;
  final int? loserLane;
  final double phase;

  /// 물고기가 타는 파도의 높이.
  final double amplitude;
  final double fishSize;

  /// [y] 높이를 따라 [from]부터 [to]까지 출렁이는 선. 레인 경계와 파도 마루에 쓴다.
  Path _waveLine(double from, double to, double y, double amp) {
    final path = Path();
    for (var x = from; x <= to; x += 4) {
      final (rise, _) = _wave(x, amp, phase);
      x == from ? path.moveTo(x, y + rise) : path.lineTo(x, y + rise);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sand = Paint()..color = const Color(0xFFE3F4FD);
    final sandDark = Paint()..color = const Color(0xFFD3ECFB);
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(nameWidth - 4, top, size.width, top + laneHeight * lanes),
      const Radius.circular(16),
    );
    canvas.save();
    canvas.clipRRect(trackRect);
    for (var i = 0; i < lanes; i++) {
      final rect = Rect.fromLTWH(
        nameWidth - 4,
        top + laneHeight * i,
        size.width,
        laneHeight,
      );
      canvas.drawRect(rect, i.isEven ? sand : sandDark);
      if (i == loserLane) {
        canvas.drawRect(rect, Paint()..color = const Color(0x33F04452));
      }
    }
    // 물고기가 타는 파도 마루: 물고기 배 아래로 흘러가는 흰 물결
    final crest = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < lanes; i++) {
      final y = top + laneHeight * i + laneHeight / 2 + fishSize * 0.42;
      canvas.drawPath(
        _waveLine(nameWidth - 4, size.width, y, amplitude),
        crest,
      );
    }
    final border = Paint()
      ..color = const Color(0xFFB5DDF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 1; i < lanes; i++) {
      canvas.drawPath(
        _waveLine(nameWidth - 4, size.width, top + laneHeight * i, 2.5),
        border,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(startX, top, 3, laneHeight * lanes),
      Paint()..color = Colors.white,
    );
    // 부표 줄
    final height = laneHeight * lanes;
    canvas.drawLine(
      Offset(finishX + 4, top),
      Offset(finishX + 4, top + height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
    const gap = 14.0;
    for (var k = 0; k * gap < height; k++) {
      canvas.drawCircle(
        Offset(finishX + 4, top + gap / 2 + k * gap),
        4.5,
        Paint()
          ..color = k.isEven ? const Color(0xFFFF8A5B) : Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.lanes != lanes ||
      old.laneHeight != laneHeight ||
      old.top != top ||
      old.startX != startX ||
      old.finishX != finishX ||
      old.loserLane != loserLane ||
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.fishSize != fishSize;
}

/// 바다 레인 이름 색.
const _deepSea = Color(0xFF1D5C86);

/// [x]에서 파도의 높이와 기울기. 파장은 90.
(double, double) _wave(double x, double amplitude, double phase) {
  const k = 2 * pi / 90;
  return (
    sin(x * k - phase) * amplitude,
    cos(x * k - phase) * amplitude * k,
  );
}
