import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../expense/domain/expense.dart';
import '../../receipt/presentation/widgets/category_badge.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/bet.dart';
import 'bet_game_screen.dart';
import 'games/game_icon.dart';

String _won(int krw) => formatMoney(krw, Currency.krw);

/// 무엇을 걸지, 누가 할지, 어떤 게임으로 할지 고른다.
/// 이미 반영한 내기가 있으면 그 설정으로 시작한다 (다시 하기).
class BetSetupScreen extends ConsumerStatefulWidget {
  const BetSetupScreen({super.key});

  @override
  ConsumerState<BetSetupScreen> createState() => _BetSetupScreenState();
}

class _BetSetupScreenState extends ConsumerState<BetSetupScreen> {
  bool _seeded = false;
  bool _treat = false;
  int _unit = 1000;
  String? _expenseId;
  Set<String> _playerIds = {};
  BetGame _game = BetGame.ddakji;

  void _seed(Trip trip, List<Member> members) {
    if (_seeded) return;
    _seeded = true;
    final ids = {for (final m in members) m.id};
    _playerIds = ids;
    final bet = trip.settlementBet;
    if (bet == null) return;
    _game = bet.game;
    switch (bet.stake) {
      case ChangeStake(:final unit):
        _unit = unit;
      case TreatStake(:final expenseId):
        _treat = true;
        _expenseId = expenseId;
    }
    final played = bet.participantIds.toSet().intersection(ids);
    if (played.length >= 2) _playerIds = played;
  }

  Future<void> _pickExpense(List<Expense> expenses) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  '어떤 지출을 쏠까요?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in expenses)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        leading: CategoryBadge(e.category, size: 40),
                        title: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          DateFormat('M월 d일').format(e.paidAt),
                          style: const TextStyle(color: AppColors.textHint),
                        ),
                        trailing: Text(
                          _won(e.totalKrw!),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        selected: e.id == _expenseId,
                        onTap: () => Navigator.pop(context, e.id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _treat = true;
        _expenseId = picked;
      });
    }
  }

  Future<void> _play(BetPlayArgs args) async {
    final applied = await context.push<bool>(
      '/settlement/bet/play',
      extra: args,
    );
    if (applied == true && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(currentTripProvider).value;
    final members = ref.watch(membersProvider).value;
    final expenses = ref.watch(expensesProvider).value;
    if (trip == null || members == null || expenses == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('미니게임으로 정하기')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _seed(trip, members);
    final rated = expenses.where((e) => (e.totalKrw ?? 0) > 0).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    final expense = rated.firstWhereOrNull((e) => e.id == _expenseId);
    final players = [
      for (final m in members)
        if (_playerIds.contains(m.id)) m,
    ];
    final BetStake? stake = _treat
        ? (expense == null ? null : TreatStake(expense.id))
        : ChangeStake(_unit);
    final unitLabel = ChangeStake(_unit).unitLabel;

    return Scaffold(
      appBar: AppBar(title: const Text('미니게임으로 정하기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '누가 조금 더 낼지\n게임으로 정해요 🎲',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '게임에서 걸린 사람이 정한 만큼 더 내요. '
                  '반영한 뒤에도 정산 화면에서 언제든 원래 정산으로 되돌릴 수 있어요.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSub,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: '무엇을 걸까요?',
            children: [
              _StakeOption(
                emoji: '🪙',
                title: '잔돈 몰아주기',
                body:
                    '각자 보낼 돈·받을 돈을 $unitLabel 단위로 맞추고, '
                    '남는 잔돈은 걸린 사람이 내요.',
                selected: !_treat,
                onTap: () => setState(() => _treat = false),
                extra: Wrap(
                  spacing: 8,
                  children: [
                    for (final unit in const [1000, 10000])
                      ChoiceChip(
                        label: Text('${ChangeStake(unit).unitLabel} 단위'),
                        selected: _unit == unit,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _unit = unit),
                      ),
                  ],
                ),
              ),
              _StakeOption(
                emoji: '🎁',
                title: '한 턱 쏘기',
                body: rated.isEmpty
                    ? '환율을 정한 지출이 생기면 고를 수 있어요.'
                    : '지출 하나를 골라요. 함께한 사람들 몫까지 걸린 사람이 내요.',
                selected: _treat,
                onTap: rated.isEmpty
                    ? null
                    : () {
                        if (expense == null) {
                          _pickExpense(rated);
                        } else {
                          setState(() => _treat = true);
                        }
                      },
                extra: _ExpenseField(
                  expense: expense,
                  onTap: () => _pickExpense(rated),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '누가 할까요?',
            trailing: Text(
              '${players.length}명',
              style: const TextStyle(fontSize: 14, color: AppColors.textSub),
            ),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in members)
                    FilterChip(
                      avatar: MemberAvatar(m, size: 24),
                      label: Text(m.name),
                      selected: _playerIds.contains(m.id),
                      showCheckmark: false,
                      onSelected: (on) => setState(
                        () =>
                            on ? _playerIds.add(m.id) : _playerIds.remove(m.id),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Text(
                  players.length < 2
                      ? '2명 이상 골라 주세요'
                      : '고른 사람끼리만 돈이 옮겨 가요. 빠진 사람은 그대로예요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: players.length < 2
                        ? AppColors.warning
                        : AppColors.textHint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '어떤 게임으로?',
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in BetGame.values) ...[
                      if (g != BetGame.values.first) const SizedBox(width: 10),
                      Expanded(
                        child: _GameCard(
                          game: g,
                          selected: _game == g,
                          onTap: () => setState(() => _game = g),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: stake == null || players.length < 2
                ? null
                : () => _play(
                    BetPlayArgs(game: _game, stake: stake, players: players),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameIcon(_game, size: 24),
                const SizedBox(width: 8),
                const Text('게임 시작'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StakeOption extends StatelessWidget {
  const _StakeOption({
    required this.emoji,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    required this.extra,
  });

  final String emoji;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback? onTap;

  /// 골랐을 때 아래에 펼치는 설정.
  final Widget extra;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryLight
                      : AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                        height: 1.4,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      alignment: Alignment.topLeft,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: extra,
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.primaryDeep : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseField extends StatelessWidget {
  const _ExpenseField({required this.expense, required this.onTap});

  final Expense? expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              if (e != null) ...[
                CategoryBadge(e.category, size: 32),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: e == null
                    ? const Text(
                        '지출 고르기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDeep,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _won(e.totalKrw!),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSub,
                            ),
                          ),
                        ],
                      ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final BetGame game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.primaryDeep : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                alignment: Alignment.centerLeft,
                child: GameIcon(game, size: 40),
              ),
              const SizedBox(height: 8),
              Text(
                game.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                game.howTo,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
