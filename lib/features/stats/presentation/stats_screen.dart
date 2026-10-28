import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/controls.dart';
import '../../../core/ui/pressable.dart';
import '../../expense/presentation/expense_actions.dart';
import '../../receipt/domain/receipt.dart';
import '../../receipt/presentation/widgets/category_badge.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/trip_stats.dart';
import 'widgets/daily_chart.dart';
import 'widgets/donut_chart.dart';

/// 통계 탭. 지금 여행의 지출을 분류·날짜·동행자·화폐별로 보여준다.
///
/// 동행자가 있으면 맨 위에서 여행 전체와 내 몫(정산에서 나눈 내 몫)을 바꿔 본다.
/// 분류를 고르면 날짜별 그래프와 큰 지출도 그 분류만 보여준다.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  bool _mine = false;
  ExpenseCategory? _category;
  DateTime? _day;

  void _setMine(bool mine) => setState(() {
        _mine = mine;
        _category = null;
        _day = null;
      });

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider);
    final members = ref.watch(membersProvider).value;
    final me = ref.watch(myMemberProvider).value;
    if (!expenses.hasValue || members == null) {
      return Scaffold(
        body: Center(
          child: expenses.hasError
              ? const Text('데이터를 불러오지 못했어요',
                  style: TextStyle(fontSize: 16, color: AppColors.textSub))
              : const AppSpinner(),
        ),
      );
    }
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    if (expenses.requireValue.isEmpty) {
      return Scaffold(body: _EmptyView(bottomPadding: bottom));
    }
    final all = tripStats(expenses.requireValue, members);
    final canSplit = members.length > 1 && me != null;
    final mine = canSplit && _mine;
    final stats = mine
        ? tripStats(expenses.requireValue, members, memberId: me.id)
        : all;
    // 지출이 바뀌어 고른 분류·날이 사라졌으면 고르지 않은 것으로 본다.
    final category =
        stats.categories.any((c) => c.category == _category) ? _category : null;
    final dayIndex = stats.days.indexWhere((d) => d.day == _day);
    final spends = [
      for (final s in stats.spends)
        if (category == null || s.expense.category == category) s,
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
          children: [
            if (canSplit) ...[
              _ScopeToggle(mine: mine, onChanged: _setMine),
              const SizedBox(height: 12),
            ],
            _SummaryCard(
                stats: stats, all: all, memberCount: members.length, mine: mine),
            if (stats.isEmpty) ...[
              const SizedBox(height: 12),
              _NoteCard(
                  text: mine
                      ? '내 몫으로 쓴 지출이 아직 없어요'
                      : '환율을 정하면 통계에 들어가요'),
            ] else ...[
              const SizedBox(height: 12),
              _CategoryCard(
                stats: stats,
                mine: mine,
                selected: category,
                onSelect: (c) => setState(() => _category = c),
              ),
              if (stats.days.length > 1) ...[
                const SizedBox(height: 12),
                _DailyCard(
                  stats: stats,
                  selected: dayIndex < 0 ? null : dayIndex,
                  focus: category,
                  onSelect: (i) =>
                      setState(() => _day = i == null ? null : stats.days[i].day),
                ),
              ],
              const SizedBox(height: 12),
              _TopCard(spends: spends, category: category, mine: mine),
              if (!mine && members.length > 1) ...[
                const SizedBox(height: 12),
                _MembersCard(members: all.members),
              ],
              if (!mine && all.currencies.any((c) => c.currency != Currency.krw)) ...[
                const SizedBox(height: 12),
                _CurrencyCard(currencies: all.currencies),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _won(int krw) => formatMoney(krw, Currency.krw);

/// "42%". 조금이라도 썼는데 반올림해서 0%면 "1% 미만".
String _percent(int percent) => percent == 0 ? '1% 미만' : '$percent%';

/// 여행 전체 | 내 몫. 고른 쪽 뒤로 연한 초록 캡슐이 미끄러진다 (아래 탭 바와 같은 모양).
class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({required this.mine, required this.onChanged});

  static const _labels = ['여행 전체', '내 몫'];

  final bool mine;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: mine ? half : 0,
              top: 0,
              bottom: 0,
              width: half,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Row(
              children: [
                for (final (i, label) in _labels.indexed)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: (i == 1) == mine,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if ((i == 1) == mine) return;
                          HapticFeedback.selectionClick();
                          onChanged(i == 1);
                        },
                        child: Center(
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: (i == 1) == mine
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: (i == 1) == mine
                                      ? AppColors.onPrimary
                                      : AppColors.textSub)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// 총액과 기간, 하루 평균·1인 평균 같은 숫자 몇 개.
/// 내 몫을 볼 때는 여행 전체에서 내 몫이 얼마인지, 1인 평균보다 많은지 적다.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.stats,
      required this.all,
      required this.memberCount,
      required this.mine});

  final TripStats stats;

  /// 여행 전체 통계. 내 몫을 볼 때 견줄 때 쓴다.
  final TripStats all;
  final int memberCount;
  final bool mine;

  String? get _period {
    final days = stats.days;
    if (days.isEmpty) return null;
    final format = DateFormat('M.d');
    final first = format.format(days.first.day);
    final last = format.format(days.last.day);
    return first == last ? first : '$first – $last · ${days.length}일';
  }

  /// "1인 평균보다 12,000원 더 썼어요"
  String _versusAverage(int average) {
    final diff = stats.totalKrw - average;
    if (diff == 0) return '1인 평균과 같아요';
    return '1인 평균보다 ${_won(diff.abs())} ${diff > 0 ? '더' : '덜'} 썼어요';
  }

  @override
  Widget build(BuildContext context) {
    final period = _period;
    final average = memberCount == 0 ? 0 : all.totalKrw ~/ memberCount;
    final share = all.totalKrw == 0
        ? 0
        : (stats.totalKrw * 100 / all.totalKrw).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(mine ? '내가 쓴 돈' : '총 지출',
                  style:
                      const TextStyle(fontSize: 14, color: AppColors.textSub)),
              const Spacer(),
              if (period != null)
                Text(period,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_won(stats.totalKrw),
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5)),
          if (mine && all.totalKrw > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '여행 전체 ${_won(all.totalKrw)} 중 $share%\n${_versusAverage(average)}',
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textHint, height: 1.45)),
            ),
          if (stats.unratedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  '환율을 아직 정하지 못한 지출 ${stats.unratedCount}건은 빠져 있어요',
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.warning)),
            ),
          if (!stats.isEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _Figure(label: '하루 평균', value: _won(stats.perDay)),
                if (memberCount > 1) ...[
                  const SizedBox(width: 8),
                  _Figure(label: '1인 평균', value: _won(average)),
                ],
                const SizedBox(width: 8),
                _Figure(
                    label: mine ? '함께한 지출' : '지출', value: '${stats.count}건'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 분류별 비율: 가운데에 총액을 둔 원형 그래프와, 많이 쓴 분류부터 금액·퍼센트 목록.
/// 그래프 조각이나 목록 줄을 누르면 그 분류를 고른다 (다시 누르면 풀린다).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard(
      {required this.stats,
      required this.mine,
      required this.selected,
      required this.onSelect});

  final TripStats stats;
  final bool mine;
  final ExpenseCategory? selected;
  final ValueChanged<ExpenseCategory?> onSelect;

  void _toggle(ExpenseCategory category) =>
      onSelect(category == selected ? null : category);

  @override
  Widget build(BuildContext context) {
    final categories = stats.categories;
    final index = categories.indexWhere((c) => c.category == selected);
    final picked = index < 0 ? null : categories[index];
    return SectionCard(
      title: '어디에 썼을까',
      children: [
        const SizedBox(height: 12),
        Center(
          child: DonutChart(
            animationKey: mine,
            slices: [
              // 그래프 옆 이름표는 짧게: '카페·간식'은 '카페'로.
              for (final c in categories)
                (
                  color: c.category.color,
                  value: c.krw,
                  label: c.category.label.split('·').first,
                ),
            ],
            selected: picked == null ? null : index,
            onSelect: (i) => i == null
                ? onSelect(null)
                : _toggle(categories[i].category),
            center: picked == null
                ? _DonutCenter(
                    title: mine ? '내 몫' : '총 지출',
                    value: _won(stats.totalKrw),
                    caption: '${categories.length}개 분류',
                  )
                : _DonutCenter(
                    icon: picked.category.icon,
                    iconColor: picked.category.color,
                    title: picked.category.label,
                    value: _won(picked.krw),
                    caption: _percent(picked.percent),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        for (final c in categories)
          _CategoryRow(
            spend: c,
            selected: c.category == selected,
            dimmed: selected != null && c.category != selected,
            onTap: () => _toggle(c.category),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _DonutCenter extends StatelessWidget {
  const _DonutCenter({
    required this.title,
    required this.value,
    required this.caption,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String value;
  final String caption;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 2),
        ],
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.text)),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(caption,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow(
      {required this.spend,
      required this.selected,
      required this.dimmed,
      required this.onTap});

  final CategorySpend spend;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: Pressable(
        scale: 0.98,
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: dimmed ? 0.45 : 1,
          duration: const Duration(milliseconds: 150),
          // 고른 줄의 회색 바탕은 카드 여백 쪽으로 조금 넓혀서, 글자는 제목과 줄을 맞춘다.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -8,
                right: -8,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.background : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _content(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return Row(
      children: [
        CategoryBadge(spend.category, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spend.category.label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              Text('${spend.count}건',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textHint)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_won(spend.krw),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            Text(_percent(spend.percent),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textHint)),
          ],
        ),
      ],
    );
  }
}

/// 날짜별 막대. 위에는 고른 날(없으면 가장 많이 쓴 날)의 금액과 많이 쓴 분류를 적는다.
class _DailyCard extends StatelessWidget {
  const _DailyCard(
      {required this.stats,
      required this.selected,
      required this.focus,
      required this.onSelect});

  final TripStats stats;
  final int? selected;
  final ExpenseCategory? focus;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = stats.days;
    final peak = stats.peakDay!;
    final shown = selected == null ? peak : days[selected!];
    final parts = shown.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final breakdown = [
      for (final p in parts.take(3))
        '${p.key.label} ${_percent((p.value * 100 / shown.krw).round())}',
    ].join(' · ');
    return SectionCard(
      title: '날짜별',
      children: [
        Text(selected == null ? '가장 많이 쓴 날' : '고른 날',
            style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(DateFormat('M월 d일 EEEE', 'ko').format(shown.day),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Text(_won(shown.krw),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        Text(shown.krw == 0 ? '쓴 돈이 없어요' : breakdown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        const SizedBox(height: 12),
        DailyChart(
          days: days,
          selected: selected,
          labeled: selected ?? days.indexOf(peak),
          focus: focus,
          onSelect: onSelect,
        ),
        if (stats.categories.length > 1) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final c in stats.categories)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: c.category.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(c.category.label,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 큰 지출 세 건. 분류를 고르면 그 분류에서 고른다. 누르면 그 지출을 연다.
class _TopCard extends StatelessWidget {
  const _TopCard(
      {required this.spends, required this.category, required this.mine});

  final List<ExpenseSpend> spends;
  final ExpenseCategory? category;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final category = this.category;
    return SectionCard(
      title: category == null ? '큰 지출' : '${category.label} 큰 지출',
      children: [
        for (final (i, s) in spends.take(3).indexed)
          _TopRow(rank: i + 1, spend: s, mine: mine),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.rank, required this.spend, required this.mine});

  final int rank;
  final ExpenseSpend spend;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final e = spend.expense;
    final total = e.totalKrw ?? 0;
    return Pressable(
      scale: 0.98,
      onTap: expenseOpener(context, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text('$rank',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHint)),
            ),
            CategoryBadge(e.category, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(
                      [
                        DateFormat('M월 d일').format(e.paidAt),
                        if (mine && spend.krw != total) '전체 ${_won(total)}',
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_won(spend.krw),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                if (!mine && e.currency != Currency.krw)
                  Text(formatMoney(e.totalMinor, e.currency),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint)),
                if (mine)
                  const Text('내 몫',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 각자 몫으로 얼마나 썼는지. 막대는 모두의 몫 중 그 사람 비율, 금액 아래에 직접 결제한 금액.
class _MembersCard extends StatelessWidget {
  const _MembersCard({required this.members});

  final List<MemberSpend> members;

  @override
  Widget build(BuildContext context) {
    final sorted = [...members]..sort((a, b) => b.used.compareTo(a.used));
    final totalUsed = members.fold(0, (sum, m) => sum + m.used);
    return SectionCard(
      title: '누가 얼마나 썼을까',
      children: [
        for (final (i, m) in sorted.indexed)
          _MemberRow(
            spend: m,
            ratio: totalUsed == 0 ? 0 : m.used / totalUsed,
            top: i == 0 && m.used > 0,
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            '굵은 금액은 품목과 함께한 사람대로 나눈 각자 몫, 결제액은 직접 결제한 금액이에요. '
            '미리 정산한 지출도 들어 있어요.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow(
      {required this.spend, required this.ratio, required this.top});

  final MemberSpend spend;
  final double ratio;

  /// 자기 몫으로 가장 많이 쓴 사람이면 이름 옆에 왕관.
  final bool top;

  static const _gold = Color(0xFFF5B400);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          MemberAvatar(spend.member, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(spend.member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    if (top) ...[
                      const SizedBox(width: 4),
                      const Icon(AppIcons.crown, size: 14, color: _gold),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                            child: ColoredBox(color: AppColors.background)),
                        FractionallySizedBox(
                          widthFactor: ratio.clamp(0, 1),
                          heightFactor: 1,
                          child: const ColoredBox(color: AppColors.primaryDeep),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 금액 폭이 달라도 막대 길이가 같게 자리를 넉넉히 잡는다.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_won(spend.used),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                Text('결제액 ${_won(spend.paid)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 화폐별로 쓴 돈과 평균 환율.
class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({required this.currencies});

  final List<CurrencySpend> currencies;

  /// "¥100 = 912원". 1단위가 몇 원 안 되는 화폐는 100·1000단위로 적는다.
  static String _rate(CurrencySpend c) {
    final rate = c.krwPerUnit;
    final unit = rate >= 10
        ? 1
        : rate >= 0.1
            ? 100
            : 1000;
    final krw = (rate * unit).round();
    return '평균 ${formatMoney(c.currency.toMinor(unit), c.currency)} = ${_won(krw)}';
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '화폐별',
      children: [
        for (final c in currencies)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: AppColors.background, shape: BoxShape.circle),
                  child: c.currency.flag.isEmpty
                      ? const Icon(AppIcons.coins,
                          size: 18, color: AppColors.textSub)
                      : Text(c.currency.flag,
                          style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.currency.nameKo} · ${c.currency.code}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                          c.currency == Currency.krw
                              ? '원화로 쓴 지출'
                              : _rate(c),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textHint)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(c.minor, c.currency),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(
                        [
                          if (c.currency != Currency.krw) _won(c.krw),
                          _percent(c.percent),
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.textHint)),
    );
  }
}

/// 아직 지출이 없을 때.
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 0, 32, bottomPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(AppIcons.statsFill,
                  size: 44, color: AppColors.primaryDeep),
            ),
            const SizedBox(height: 20),
            const Text('아직 통계가 없어요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              '지출을 기록하면 어디에 얼마나 썼는지\n한눈에 보여 드려요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
