import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../trip/domain/trip.dart';

/// 파도타기: 한 사람이 물고기 한 마리씩 맡아 파도를 타고, 가장 늦게 도착한 사람이 걸린다.
///
/// 경주 전체를 미리 계산해 두고 그대로 보여준다. 물고기마다 속도가 수시로 바뀌고,
/// 가끔 졸거나(💤) 쌩 하고 질주한다(💨). 무작위로 몇몇 레인에서 장애물(낚싯바늘·상어·소용돌이)이
/// 갑자기 나타나 뒤로 밀린다. 뒤처질수록 조금 빨라져서 끝까지 엎치락뒤치락한다.
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
/// 상어는 장애물이라 넣지 않는다.
const _fish = [
  '🐟', '🐠', '🐡', '🐬', '🐳', '🐋', //
  '🦭', '🐙', '🦑', '🦐', '🦀',
];

enum _Phase { ready, countdown, running, finished }

/// 헤엄치는 상태. 졸면 멈추고, 큰 파도를 타면 빨라지고, 장애물에 부딪히면 뒤로 밀린다.
enum _Stride { run, nap, dash, bump }

/// 물고기 바로 앞에 갑자기 나타나는 장애물. 부딪히면 물고기가 뒤로 밀리고 물방울이 터진다.
/// 상어는 깊은 데서 헤엄쳐 오고, 낚시꾼의 바늘은 위에서 내려오고, 소용돌이는 빙글 생겨난다.
enum _Hazard {
  hook('🪝'),
  shark('🦈'),
  whirlpool('🌀');

  const _Hazard(this.emoji);
  final String emoji;
}

class _Obstacle {
  _Obstacle(this.at, this.hazard);

  /// 레인 위 자리 (0~1). 물고기 코끝이 여기에 닿으면 부딪힌다.
  final double at;
  final _Hazard hazard;

  /// 부딪힌 프레임. 끝까지 못 만나면 null.
  int? hitFrame;
}

/// 장애물이 부딪히기 몇 프레임 전부터 보이는지. 미리 보이지 않고 코앞에서 나타난다:
/// 처음엔 물 밑 그림자와 동심원이, [_emergeFrames] 전부터는 장애물이 솟아오른다.
const _appearFrames = 34;
const _emergeFrames = 20;

/// 물결이 처음 모양으로 돌아오기까지 도는 바퀴 수. 위상에 곱하는 계수(0.8, 0.2, 0.5, 1.2, 1.8)와
/// 곱해 모두 정수가 되어야 이음매 없이 이어진다.
const _seaTurns = 50;

/// 부딪힌 장애물이 물보라를 남기고 사라지는 데 걸리는 프레임.
const _splashFrames = 36;

/// 미리 계산한 경주. 1/60초마다 각자 어디까지 왔는지 적어 둔다.
class _Race {
  _Race._(this.progress, this.strides, this.finishTimes, this.obstacles);

  static const fps = 60;

  /// [runner][frame] → 0~1
  final List<List<double>> progress;
  final List<List<_Stride>> strides;

  /// 결승선을 넘은 시각(초). 같은 프레임에 들어와도 넘은 순간으로 순위를 가린다.
  final List<double> finishTimes;

  /// [runner] 레인의 장애물.
  final List<List<_Obstacle>> obstacles;

  int get frames => progress.first.length;

  /// 들어온 순서대로 달린 사람 번호.
  List<int> get order =>
      [for (var i = 0; i < finishTimes.length; i++) i]
        ..sort((a, b) => finishTimes[a].compareTo(finishTimes[b]));

  factory _Race.simulate(int runners, Random random) {
    const dt = 1 / fps;
    const base = 1 / 11; // 평균 11초쯤 헤엄치고, 장애물에 밀린 만큼 더 걸린다.
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

    // 장애물은 레인마다 0~3개를 무작위로 둔다. 운 나쁜 사람만 여러 번 만날 수도 있다.
    // 경주마다 적어도 하나는 나오게 한다.
    _Hazard hazard() => _Hazard.values[random.nextInt(_Hazard.values.length)];
    List<_Obstacle> lay(int count) {
      final spots = <double>[];
      for (var tries = 0; spots.length < count && tries < 30; tries++) {
        final at = between(0.15, 0.88);
        if (spots.every((s) => (s - at).abs() > 0.12)) spots.add(at);
      }
      return [for (final at in spots..sort()) _Obstacle(at, hazard())];
    }

    int howMany() {
      final roll = random.nextDouble();
      return roll < 0.3 ? 0 : (roll < 0.65 ? 1 : (roll < 0.9 ? 2 : 3));
    }

    final obstacles = [for (var i = 0; i < runners; i++) lay(howMany())];
    if (obstacles.every((lane) => lane.isEmpty)) {
      obstacles[random.nextInt(runners)] = lay(1);
    }

    for (var frame = 0; frame < fps * 60; frame++) {
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
          final hit = step <= 0
              ? null
              : obstacles[i]
                  .where((o) =>
                      o.hitFrame == null && pos[i] < o.at && pos[i] + step >= o.at)
                  .firstOrNull;
          if (hit != null) {
            // 장애물에 닿은 자리에서 잠깐 뒤로 밀려난다.
            hit.hitFrame = frame;
            pos[i] = hit.at;
            final knock = between(0.05, 0.08);
            final seconds = between(0.4, 0.55);
            segment(i, _Stride.bump, -knock / seconds / base, seconds);
          } else if (pos[i] + step >= 1) {
            finish[i] = (frame + (1 - pos[i]) / step) * dt;
            pos[i] = 1;
          } else {
            pos[i] = max(0, pos[i] + step);
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
    return _Race._(progress, strides, finish, obstacles);
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

  /// 물빛과 해초는 출발 전에도 계속 일렁인다. 1초에 5.4라디안씩 흘러간다.
  late final AnimationController _sea = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_seaTurns * 2 * pi / 5.4 * 1000).round()),
  )..repeat();

  /// 화면을 열 때 경주를 미리 정해 둔다. 장애물은 부딪히기 직전에야 나타난다.
  late final _Race _race = _Race.simulate(widget.players.length, _random);
  int _frame = 0;
  int _lastCount = 0;

  /// 장애물에 부딪힌 순간마다 진동을 한 번씩 준다.
  int _lastHitFrame = -1;
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
    _sea.dispose();
    super.dispose();
  }

  void _start() {
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.countdown;
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
    final race = _race;
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
    if (race.obstacles.any((lane) => lane.any((o) =>
        o.hitFrame != null && o.hitFrame! > _lastHitFrame && o.hitFrame! <= frame))) {
      HapticFeedback.mediumImpact();
    }
    _lastHitFrame = frame;
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
                      '가장 늦게 도착한 물고기가 걸려요. 갑자기 나타나는 낚싯바늘·상어·소용돌이에 부딪히면 뒤로 밀려요',
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
                  child: AnimatedBuilder(
                    animation: _sea,
                    builder: (context, _) => _Track(
                      players: widget.players,
                      emoji: _emoji,
                      race: _race,
                      frame:
                          _phase == _Phase.ready || _phase == _Phase.countdown
                              ? null
                              : _frame,
                      ranks: _ranks,
                      loser: _phase == _Phase.finished ? _race.order.last : null,
                      phase: _sea.value * 2 * pi * _seaTurns,
                    ),
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

/// 레인을 그리는 데 필요한 자리 계산.
class _Lanes {
  const _Lanes({
    required this.top,
    required this.lane,
    required this.fish,
    required this.startX,
    required this.finishX,
  });

  final double top;

  /// 레인 하나의 높이.
  final double lane;

  /// 물고기 크기.
  final double fish;
  final double startX;
  final double finishX;

  double laneTop(int i) => top + lane * i;
  double center(int i) => top + lane * i + lane / 2;

  /// 모래 바닥 높이.
  double floor(int i) => laneTop(i) + lane * 0.9;

  /// 장애물 크기.
  double get hazard => fish * 0.9;

  /// 레인 위 자리(0~1)의 x. 물고기 코끝과 장애물 앞면이 여기에 온다.
  double x(double p) => startX + p * (finishX - startX);

  /// [i]번 레인 물고기가 헤엄치며 살짝 오르내리는 높이와 기울기.
  (double, double) bob(int i, double x, double phase) {
    final a = lane * 0.035;
    final t = phase * 0.8 + i * 1.3 + x * 0.025;
    return (sin(t) * a, cos(t) * a * 0.025);
  }

  @override
  bool operator ==(Object other) =>
      other is _Lanes &&
      other.top == top &&
      other.lane == lane &&
      other.fish == fish &&
      other.startX == startX &&
      other.finishX == finishX;

  @override
  int get hashCode => Object.hash(top, lane, fish, startX, finishX);
}

/// 낚싯바늘이 내려온 정도에 따른 세로 이동 (위가 음수). 나타날 때 줄을 타고 내려와 출렁이고,
/// 물고기가 걸리면 확 끌려 올라간다.
double _hookOffset(int since, double lane) {
  final enter = since >= 0
      ? 1.0
      : ((since + _emergeFrames) / _emergeFrames).clamp(0.0, 1.0);
  final leave = since <= 0 ? 0.0 : since / _splashFrames;
  return -(1 - Curves.easeOutBack.transform(enter)) * lane * 0.6 -
      Curves.easeIn.transform(leave) * lane * 1.2;
}

/// 바닷속 레인. 왼쪽에 이름, 오른쪽 끝에 부표 결승선. 물빛과 해초는 출발 전에도 일렁인다.
class _Track extends StatelessWidget {
  const _Track({
    required this.players,
    required this.emoji,
    required this.race,
    required this.frame,
    required this.ranks,
    required this.loser,
    required this.phase,
  });

  final List<Member> players;
  final List<String> emoji;
  final _Race race;

  /// 출발 전에는 null.
  final int? frame;
  final Map<int, int> ranks;
  final int? loser;

  /// 물결이 흘러간 정도.
  final double phase;

  static const _nameWidth = 58.0;
  static const _finishInset = 40.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD9F1FD), Color(0xFFC2E6F9)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFA3D6F2), width: 2),
      ),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, box) {
          final n = players.length;
          final lane = min(96.0, box.maxHeight / n);
          final size = (lane * 0.55).clamp(20.0, 50.0);
          final g = _Lanes(
            top: (box.maxHeight - lane * n) / 2,
            lane: lane,
            fish: size,
            startX: _nameWidth + size,
            finishX: box.maxWidth - _finishInset,
          );
          final f = frame;
          final leader = f == null
              ? null
              : [for (var i = 0; i < n; i++) i].reduce(
                  (a, b) =>
                      race.progress[a][f] >= race.progress[b][f] ? a : b,
                );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SeaPainter(
                    g: g,
                    lanes: n,
                    nameWidth: _nameWidth,
                    loserLane: loser,
                    phase: phase,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _SprayPainter(
                    g: g,
                    race: race,
                    frame: f,
                    phase: phase,
                    front: false,
                  ),
                ),
              ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: 6,
                  top: g.laneTop(i),
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
              for (var i = 0; i < n; i++)
                for (final o in race.obstacles[i]) ?_obstacle(o, i, g),
              for (var i = 0; i < n; i++) _runner(i, g, leader == i),
              for (var i = 0; i < n; i++)
                if (ranks[i] case final rank?)
                  Positioned(
                    left: g.finishX + 15,
                    top: g.laneTop(i) + (lane - 22) / 2,
                    child: _RankBadge(rank: rank, last: loser == i),
                  ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SprayPainter(
                      g: g,
                      race: race,
                      frame: f,
                      phase: phase,
                      front: true,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 상어는 깊은 데서 헤엄쳐 다가오고 부딪힌 뒤 멀어진다. 낚싯바늘은 위에서 내려와 걸면 끌려 올라간다.
  /// 소용돌이는 [_SprayPainter]가 그린다. 나타나기 전과 사라진 뒤에는 null.
  Widget? _obstacle(_Obstacle o, int i, _Lanes g) {
    final f = frame;
    final hitFrame = o.hitFrame;
    if (f == null || hitFrame == null) return null;
    final since = f - hitFrame;
    if (since < -_appearFrames || since > _splashFrames) return null;
    final s = g.hazard;
    final enter = since >= 0
        ? 1.0
        : ((since + _emergeFrames) / _emergeFrames).clamp(0.0, 1.0);
    final leave = since <= 0 ? 0.0 : since / _splashFrames;
    final warn = ((since + _appearFrames) / 8).clamp(0.0, 1.0);
    final Widget? sprite = switch (o.hazard) {
      _Hazard.whirlpool => null,
      _Hazard.shark => Opacity(
          opacity: (min(1.0, enter * 2) * (1 - leave)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              (1 - Curves.easeOutCubic.transform(enter)) * s * 0.7 +
                  Curves.easeIn.transform(leave) * s * 1.6,
              sin(f * 0.2) * s * 0.04,
            ),
            child: Transform.scale(
              scale: 0.6 + 0.4 * Curves.easeOutBack.transform(enter),
              child: Transform.rotate(
                angle: sin(f * 0.35) * 0.06,
                child: _emojiBox(o.hazard.emoji),
              ),
            ),
          ),
        ),
      _Hazard.hook => Opacity(
          opacity: min(1.0, enter * 3) * (1 - leave * 0.6),
          child: Transform.translate(
            offset: Offset(0, _hookOffset(since, g.lane)),
            child: Transform.rotate(
              angle: sin(f * 0.12) * 0.15,
              alignment: Alignment.topCenter,
              child: _emojiBox(o.hazard.emoji),
            ),
          ),
        ),
    };
    return Positioned(
      left: g.x(o.at),
      top: g.center(i) - s / 2,
      width: s,
      height: s,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (sprite != null && enter > 0) sprite,
          if (since < 6)
            Positioned(
              left: s * 0.25,
              top: -s * 0.7,
              child: Transform.scale(
                scale: Curves.easeOutBack.transform(warn),
                child: Text('❗', style: TextStyle(fontSize: s * 0.45)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _runner(int i, _Lanes g, bool leading) {
    final f = frame;
    final p = f == null ? 0.0 : race.progress[i][f];
    final stride = f == null ? _Stride.run : race.strides[i][f];
    final size = g.fish;
    final x = g.x(p) - size;
    final (rise, slope) = g.bob(i, x + size / 2, phase);
    return Positioned(
      left: x,
      top: g.center(i) - size / 2 + rise,
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(
            // 부딪혀서 밀려나는 동안은 어지러워서 흔들린다.
            angle: atan(slope) +
                (stride == _Stride.bump && f != null ? sin(f * 0.9) * 0.35 : 0),
            child: Transform.flip(flipX: true, child: _emojiBox(emoji[i])),
          ),
          if (stride == _Stride.nap && f != null)
            Positioned(
              right: -size * 0.35,
              top: -size * 0.35 + sin(f * 0.15) * 2,
              child: Text('💤', style: TextStyle(fontSize: size * 0.45)),
            ),
          if (stride == _Stride.bump && f != null)
            Positioned(
              left: size * 0.2,
              top: -size * 0.5,
              child: Text('💫', style: TextStyle(fontSize: size * 0.45)),
            ),
          if (stride == _Stride.dash && f != null)
            // 질주: 꼬리 뒤로 바람이 훅 뿜어져 나간다.
            Positioned(
              left: -size * 0.62 - sin(f * 0.5).abs() * size * 0.06,
              top: size * 0.22,
              child: Transform.flip(
                flipX: true,
                child: Text('💨', style: TextStyle(fontSize: size * 0.5)),
              ),
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

Widget _emojiBox(String emoji) =>
    FittedBox(child: Text(emoji, style: const TextStyle(fontSize: 40)));

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

/// 바닷속: 아래로 갈수록 깊어지는 물빛, 위에서 비스듬히 들어오는 햇살, 모래 바닥과 흔들리는 해초,
/// 천천히 올라가는 물방울, 출발선 밧줄과 결승선 부표.
class _SeaPainter extends CustomPainter {
  _SeaPainter({
    required this.g,
    required this.lanes,
    required this.nameWidth,
    required this.loserLane,
    required this.phase,
  });

  final _Lanes g;
  final int lanes;
  final double nameWidth;
  final int? loserLane;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final left = nameWidth - 4;
    final right = size.width;
    final bottom = g.top + g.lane * lanes;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTRB(left, g.top, right, bottom),
      const Radius.circular(16),
    ));
    for (var i = 0; i < lanes; i++) {
      final y0 = g.laneTop(i);
      final y1 = y0 + g.lane;
      final rect = Rect.fromLTRB(left, y0, right, y1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            i.isEven
                ? const [Color(0xFFD6F1FD), Color(0xFF8ED0F0)]
                : const [Color(0xFFCCEDFC), Color(0xFF86CBEE)],
          ),
      );
    }
    _sunbeams(canvas, left, right, bottom);
    for (var i = 0; i < lanes; i++) {
      _seabed(canvas, i, left, right);
      _ambientBubbles(canvas, i, left, right);
      if (i == loserLane) {
        canvas.drawRect(
          Rect.fromLTRB(left, g.laneTop(i), right, g.laneTop(i) + g.lane),
          Paint()..color = const Color(0x2EF04452),
        );
      }
    }
    for (var i = 1; i < lanes; i++) {
      canvas.drawLine(
        Offset(left, g.laneTop(i)),
        Offset(right, g.laneTop(i)),
        Paint()
          ..color = const Color(0x8CEAF8FF)
          ..strokeWidth = 1.5,
      );
    }
    // 출발선: 흰 밧줄에 노란 찌
    canvas.drawLine(
      Offset(g.startX + 1, g.top),
      Offset(g.startX + 1, bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 2,
    );
    for (var y = g.top + 6; y < bottom; y += 12) {
      canvas.drawCircle(
          Offset(g.startX + 1, y), 2.2, Paint()..color = const Color(0xFFFFD166));
    }
    // 결승선: 줄에 꿴 둥근 부표
    canvas.drawLine(
      Offset(g.finishX + 4, g.top),
      Offset(g.finishX + 4, bottom),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
    var k = 0;
    for (var y = g.top + 7; y < bottom; y += 14, k++) {
      final c = Offset(g.finishX + 4, y);
      final base = k.isEven ? const Color(0xFFFF7A45) : Colors.white;
      canvas.drawCircle(
        c,
        5,
        Paint()
          ..shader = ui.Gradient.radial(c.translate(-1.6, -1.6), 6,
              [Color.lerp(base, Colors.white, 0.65)!, base]),
      );
      canvas.drawCircle(
        c,
        5,
        Paint()
          ..color = const Color(0x26000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
    canvas.restore();
  }

  /// 위에서 비스듬히 내려오는 햇살 몇 줄기. 천천히 흔들린다.
  void _sunbeams(Canvas canvas, double left, double right, double bottom) {
    final height = bottom - g.top;
    final width = right - left;
    for (var r = 0; r < 4; r++) {
      final x0 = left + width * (0.12 + r * 0.24) + sin(phase * 0.2 + r * 1.7) * 10;
      final w = width * (0.06 + 0.03 * (r % 2));
      final lean = height * 0.3;
      final beam = Path()
        ..moveTo(x0, g.top)
        ..lineTo(x0 + w, g.top)
        ..lineTo(x0 + w - lean, bottom)
        ..lineTo(x0 - lean - w * 0.6, bottom)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, g.top),
            Offset(0, bottom),
            [
              Colors.white.withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0),
            ],
          ),
      );
    }
  }

  /// 레인 바닥의 모래 둔덕과 흔들리는 해초.
  void _seabed(Canvas canvas, int i, double left, double right) {
    final y1 = g.laneTop(i) + g.lane;
    final floor = g.floor(i);
    final sand = Path()..moveTo(left, y1);
    for (var x = left; x <= right + 6; x += 6) {
      sand.lineTo(x, floor + sin(x * 0.045 + i * 2.1) * g.lane * 0.025);
    }
    sand
      ..lineTo(right + 6, y1)
      ..close();
    canvas.drawPath(
      sand,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, floor - g.lane * 0.03),
            Offset(0, y1), const [Color(0xFFF6E7BE), Color(0xFFE3CC92)]),
    );
    // 해초: 레인마다 자리를 조금씩 다르게
    for (var k = 0; k < 3; k++) {
      final x = left + (right - left) * ((0.21 + k * 0.31 + i * 0.13) % 1.0);
      final h = g.lane * (0.28 + 0.1 * ((k + i) % 3));
      final sway = sin(phase * 0.5 + k * 1.3 + i) * g.lane * 0.07;
      for (final (dx, color, width) in [
        (0.0, const Color(0xFF3FA778), 3.2),
        (4.0, const Color(0xFF66C194), 2.4),
      ]) {
        canvas.drawPath(
          Path()
            ..moveTo(x + dx, floor + 2)
            ..quadraticBezierTo(x + dx + sway * 1.4, floor - h * 0.5,
                x + dx + sway, floor - h * (dx == 0 ? 1 : 0.75)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  /// 바닥에서 천천히 올라가는 작은 물방울.
  void _ambientBubbles(Canvas canvas, int i, double left, double right) {
    final y0 = g.laneTop(i);
    for (var k = 0; k < 4; k++) {
      final rise = (phase * 0.1 / (2 * pi) + k * 0.27 + i * 0.19) % 1.0;
      final x = left +
          (right - left) * ((0.08 + k * 0.23 + i * 0.37) % 1.0) +
          sin(rise * 9 + k) * 3;
      final y = g.floor(i) - rise * (g.floor(i) - y0 - 4);
      canvas.drawCircle(
        Offset(x, y),
        1.3 + (k % 2),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6 * (1 - rise * 0.7))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_SeaPainter old) =>
      old.g != g ||
      old.lanes != lanes ||
      old.loserLane != loserLane ||
      old.phase != phase;
}

/// 물고기의 모래 위 그림자·물방울 꼬리·질주할 때의 물살 줄과 소용돌이·낚싯줄을 그리고([front]가
/// false), 부딪힐 때 터지는 물방울과 충격 링을 물고기·장애물 위에 그린다([front]가 true).
class _SprayPainter extends CustomPainter {
  _SprayPainter({
    required this.g,
    required this.race,
    required this.frame,
    required this.phase,
    required this.front,
  });

  final _Lanes g;
  final _Race race;
  final int? frame;
  final double phase;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < race.progress.length; i++) {
      if (!front) _trail(canvas, i);
      final f = frame;
      if (f == null) continue;
      for (var k = 0; k < race.obstacles[i].length; k++) {
        final o = race.obstacles[i][k];
        final hit = o.hitFrame;
        if (hit == null) continue;
        final since = f - hit;
        if (since < -_appearFrames || since > _splashFrames) continue;
        final x = g.x(o.at);
        if (front) {
          if (since >= 0) _burst(canvas, Offset(x, g.center(i)), since, i * 31 + k);
        } else if (o.hazard == _Hazard.whirlpool) {
          _vortex(canvas, Offset(x + g.hazard / 2, g.center(i)), since);
        } else if (o.hazard == _Hazard.hook && since >= -_emergeFrames) {
          // 위에서 내려온 낚싯줄
          final eye = g.center(i) - g.hazard * 0.45 + _hookOffset(since, g.lane);
          final sway = sin(f * 0.12) * 0.15;
          canvas.drawLine(
            Offset(x + g.hazard * 0.5 + sway * 6, g.laneTop(i)),
            Offset(x + g.hazard * 0.5, eye),
            Paint()
              ..color = const Color(0xCCEFF7FC)
              ..strokeWidth = 1.2,
          );
        }
      }
    }
  }

  /// 모래 위 그림자와, 꼬리 뒤로 올라가는 물방울. 빠를수록 물방울이 많고 질주하면 물살 줄이 생긴다.
  void _trail(Canvas canvas, int i) {
    final f = frame;
    final p = f == null ? 0.0 : race.progress[i][f];
    final nose = g.x(p);
    final body = nose - g.fish / 2;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(body, g.floor(i) + g.lane * 0.03),
          width: g.fish * 0.8,
          height: g.lane * 0.06),
      Paint()
        ..color = const Color(0x33104A6E)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    if (f == null || f == 0 || p >= 1) return;
    final speed = (p - race.progress[i][f - 1]) * (g.finishX - g.startX);
    if (speed <= 0.05) return;
    final tail = nose - g.fish * 0.85;
    final y = g.center(i) + g.bob(i, body, phase).$1;
    final len = (speed * 22).clamp(g.fish * 0.5, g.fish * 2.2);
    final count = speed > 1.2 ? 8 : 5;
    for (var j = 0; j < count; j++) {
      final age = ((f + j * (30 ~/ count)) % 30) / 30;
      final c = Offset(
        tail - age * len,
        y - age * g.fish * 0.45 + sin(age * 8 + j * 2) * 2.5,
      );
      final r = 1.2 + (1 - age) * (1.2 + (j % 3) * 0.6);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: (1 - age) * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      canvas.drawCircle(c.translate(-r * 0.35, -r * 0.35), r * 0.25,
          Paint()..color = Colors.white.withValues(alpha: (1 - age) * 0.7));
    }
    if (speed > 1.2) {
      final streak = Paint()
        ..shader = ui.Gradient.linear(
          Offset(tail, 0),
          Offset(tail - len * 1.2, 0),
          [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0)],
        )
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (final dy in const [-0.22, 0.0, 0.22]) {
        canvas.drawLine(Offset(tail, y + g.fish * dy),
            Offset(tail - len * 1.2, y + g.fish * dy), streak);
      }
    }
  }

  /// 물속에서 도는 소용돌이. 나타날 때 커지고, 부딪힌 뒤 줄어들며 사라진다.
  void _vortex(Canvas canvas, Offset c, int since) {
    final grow = since < 0
        ? Curves.easeOutBack.transform(
            ((since + _emergeFrames) / _emergeFrames).clamp(0.0, 1.0))
        : 1 - Curves.easeIn.transform(since / _splashFrames);
    if (grow <= 0.01) return;
    final r = g.hazard * 0.62 * grow;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, 0.85);
    canvas.drawCircle(
      Offset.zero,
      r * 1.2,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          r * 1.2,
          const [Color(0xCC0E4A78), Color(0x992F86C2), Color(0x003FA0DA)],
          const [0, 0.5, 1],
        ),
    );
    final spin = -phase * 1.2;
    final arm = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.4, r * 0.1)
      ..strokeCap = StrokeCap.round;
    for (var a = 0; a < 3; a++) {
      final path = Path();
      for (var n = 0; n <= 25; n++) {
        final t = n / 25;
        final angle = spin + a * 2 * pi / 3 + t * 1.7 * pi;
        final rr = r * (0.1 + 0.95 * t);
        final pt = Offset(cos(angle) * rr, sin(angle) * rr);
        n == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, arm);
    }
    // 소용돌이에 휩쓸려 도는 작은 물방울
    for (var b = 0; b < 6; b++) {
      final angle = spin * 1.5 + b * pi / 3;
      final rr = r * (0.55 + 0.4 * ((b % 3) / 2));
      canvas.drawCircle(Offset(cos(angle) * rr, sin(angle) * rr), 1.5,
          Paint()..color = Colors.white.withValues(alpha: 0.8));
    }
    canvas.restore();
  }

  /// 부딪힌 자리에서 퍼지는 충격 링과, 사방으로 터졌다가 위로 떠오르는 물방울.
  void _burst(Canvas canvas, Offset c, int since, int seed) {
    final s = g.hazard;
    final life = since / _splashFrames;
    if (since < 12) {
      final w = s * (0.4 + since * 0.09);
      canvas.drawCircle(
        c,
        w / 2,
        Paint()
          ..color = Colors.white.withValues(alpha: 1 - since / 12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    final random = Random(seed);
    final t = since.toDouble();
    for (var j = 0; j < 14; j++) {
      final angle = (j + random.nextDouble()) / 14 * 2 * pi;
      final speed = s * (0.03 + random.nextDouble() * 0.04) * (1 - life * 0.5);
      final bubble = c +
          Offset(cos(angle) * speed * t,
              sin(angle) * speed * t - 0.5 * s * 0.004 * t * t);
      final r = (1.5 + random.nextDouble() * 2.5) * (1 - life * 0.4);
      final alpha = (1 - life).clamp(0.0, 1.0);
      canvas.drawCircle(
        bubble,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(bubble.translate(-r * 0.35, -r * 0.35), r * 0.28,
          Paint()..color = Colors.white.withValues(alpha: alpha * 0.8));
    }
  }

  @override
  bool shouldRepaint(_SprayPainter old) => true;
}

/// 바다 레인 이름 색.
const _deepSea = Color(0xFF1D5C86);
