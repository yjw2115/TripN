import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/bet.dart';
import '../domain/settlement.dart';
import 'games/confetti.dart';
import 'games/ddakji_game.dart';
import 'games/game_icon.dart';
import 'games/wave_race_game.dart';

/// 내기 설정 화면에서 고른 것.
class BetPlayArgs {
  const BetPlayArgs({
    required this.game,
    required this.stake,
    required this.players,
  });

  final BetGame game;
  final BetStake stake;
  final List<Member> players;
}

String _won(int krw) => formatMoney(krw, Currency.krw);

/// 미니게임을 하고, 걸린 사람이 나오면 정산에 반영할지 묻는다.
/// 반영하면 여행 문서에 저장하고 true로 닫는다. 반영하지 않고 나가면 아무것도 바뀌지 않는다.
class BetGameScreen extends ConsumerStatefulWidget {
  const BetGameScreen({super.key, required this.args, this.random});

  final BetPlayArgs args;

  /// 테스트에서 고정한다.
  final Random? random;

  @override
  ConsumerState<BetGameScreen> createState() => _BetGameScreenState();
}

class _BetGameScreenState extends ConsumerState<BetGameScreen> {
  int _round = 0;
  Member? _loser;
  List<Member>? _ranking;

  void _finish(Member loser, [List<Member>? ranking]) => setState(() {
    _loser = loser;
    _ranking = ranking;
  });

  void _again() => setState(() {
    _round++;
    _loser = null;
    _ranking = null;
  });

  SettlementBet _betFor(Member loser) => SettlementBet(
    game: widget.args.game,
    stake: widget.args.stake,
    loserId: loser.id,
    participantIds: [for (final p in widget.args.players) p.id],
  );

  void _apply(Trip trip, SettlementBet bet) {
    reportWriteErrors(
      context,
      ref.read(tripRepositoryProvider).setSettlementBet(trip.id, bet),
    );
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.args.game;
    final background = switch (game) {
      BetGame.ddakji => const Color(0xFFFBF7F0),
      BetGame.wave => const Color(0xFFEFF9FF),
    };
    final loser = _loser;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        title: Row(
          children: [
            GameIcon(game, size: 26),
            const SizedBox(width: 8),
            Text(game.label),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey(_round),
              child: switch (game) {
                BetGame.ddakji => DdakjiGame(
                  players: widget.args.players,
                  random: widget.random,
                  onLoser: _finish,
                ),
                BetGame.wave => WaveRaceGame(
                  players: widget.args.players,
                  random: widget.random,
                  onFinish: (ranking) => _finish(ranking.last, ranking),
                ),
              },
            ),
          ),
          if (loser != null) ...[
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 250),
                builder: (context, t, _) =>
                    ColoredBox(color: Colors.black.withValues(alpha: 0.28 * t)),
              ),
            ),
            Positioned.fill(child: ConfettiBurst(key: ValueKey(_round))),
            Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('result-$_round'),
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => FractionalTranslation(
                  translation: Offset(0, t),
                  child: child,
                ),
                child: _ResultPanel(
                  game: game,
                  loser: loser,
                  ranking: _ranking,
                  bet: _betFor(loser),
                  onApply: _apply,
                  onAgain: _again,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultPanel extends ConsumerWidget {
  const _ResultPanel({
    required this.game,
    required this.loser,
    required this.ranking,
    required this.bet,
    required this.onApply,
    required this.onAgain,
  });

  final BetGame game;
  final Member loser;
  final List<Member>? ranking;
  final SettlementBet bet;
  final void Function(Trip trip, SettlementBet bet) onApply;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(currentTripProvider).value;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final expenses = ref.watch(expensesProvider).value ?? const [];
    final applied = settle(expenses, members, bet: bet).bet;
    final stake = bet.stake;
    final effect = switch ((applied, stake)) {
      (null, _) => '내기에 건 지출을 찾지 못했어요',
      (final a?, ChangeStake(:final unitLabel)) =>
        a.amount > 0
            ? '잔돈 ${_won(a.amount)}을 몰아서 내요\n다른 사람은 $unitLabel 단위로 딱 떨어져요'
            : '맞출 잔돈이 없어서 더 낼 돈은 없어요',
      (final a?, TreatStake()) =>
        "'${a.expense!.title}' ${_won(a.expense!.totalKrw!)} 중\n"
            '다른 사람 몫 ${_won(a.amount)}을 대신 내요',
    };
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  MemberAvatar(loser, size: 76),
                  Positioned(
                    right: -8,
                    bottom: -4,
                    child: Text(
                      game == BetGame.ddakji ? '😱' : '🐡',
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${loser.name}님 당첨!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                effect,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSub,
                  height: 1.45,
                ),
              ),
              if (ranking case final ranking?) ...[
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < ranking.length; i++)
                      _RankChip(
                        rank: i + 1,
                        member: ranking[i],
                        last: i == ranking.length - 1,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: trip == null || applied == null
                    ? null
                    : () => onApply(trip, bet),
                child: const Text('정산에 반영하기'),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: onAgain, child: const Text('다시 하기')),
              Text(
                trip?.settlementBet == null
                    ? '반영해도 정산 화면에서 언제든 원래대로 되돌릴 수 있어요'
                    : '지금 반영된 내기 결과는 이 결과로 바뀌어요',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textHint),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({
    required this.rank,
    required this.member,
    required this.last,
  });

  final int rank;
  final Member member;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      _ when last => '🐡',
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '$rank',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: last ? const Color(0xFFFFEBEC) : AppColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        last ? '$medal ${member.name} 꼴찌' : '$medal ${member.name}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: last ? AppColors.danger : AppColors.textSub,
        ),
      ),
    );
  }
}
