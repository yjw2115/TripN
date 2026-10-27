import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../../core/money/currency.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../receipt/domain/receipt.dart';
import '../../../receipt/presentation/widgets/category_badge.dart';
import '../../domain/trip_stats.dart';

/// 날마다 쓴 돈을 분류별로 쌓은 막대. 아래부터 분류 순서대로 쌓는다.
///
/// 막대를 누르면 [onSelect]로 그날의 순서를 주고(다시 누르면 null), 다른 날은 흐려진다.
/// [focus] 분류를 고르면 그 분류만 진하게 보인다.
/// 금액은 [labeled] 날 막대 위에만 적는다. 나머지는 눌러서 본다.
/// 날이 많아 다 들어가지 않으면 옆으로 밀어 본다 (처음에는 최근 날이 보인다).
class DailyChart extends StatelessWidget {
  const DailyChart({
    super.key,
    required this.days,
    required this.onSelect,
    this.selected,
    this.labeled,
    this.focus,
  });

  final List<DaySpend> days;
  final ValueChanged<int?> onSelect;
  final int? selected;
  final int? labeled;
  final ExpenseCategory? focus;

  static const _barHeight = 120.0;
  static const _labelHeight = 24.0;
  static const _minSlot = 36.0;
  static const _barWidth = 20.0;

  @override
  Widget build(BuildContext context) {
    final peak = days.map((d) => d.krw).maxOrNull ?? 0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final fits = _minSlot * days.length <= width;
      final slot = fits ? width / days.length : _minSlot;
      final columns = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, day) in days.indexed)
            _column(i, day, slot, peak),
        ],
      );
      if (fits) return columns;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: columns,
      );
    });
  }

  Widget _column(int i, DaySpend day, double slot, int peak) {
    final isSelected = i == selected;
    final dimmed = selected != null && !isSelected;
    final previous = i == 0 ? null : days[i - 1].day;
    final dayLabel = previous == null || previous.month != day.day.month
        ? DateFormat('M.d').format(day.day)
        : '${day.day.day}';
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${DateFormat('M월 d일', 'ko').format(day.day)} ${formatMoney(day.krw, Currency.krw)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(isSelected ? null : i),
        child: SizedBox(
          width: slot,
          child: Column(
            children: [
              SizedBox(
                height: _barHeight + _labelHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (i == labeled && day.krw > 0)
                      Container(
                        height: 16,
                        margin: const EdgeInsets.only(bottom: 4),
                        alignment: Alignment.bottomCenter,
                        child: Text(formatWonCompact(day.krw),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text)),
                      ),
                    AnimatedOpacity(
                      opacity: dimmed ? 0.35 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: _StackedBar(
                        day: day,
                        height: peak <= 0 ? 0 : day.krw / peak * _barHeight,
                        width: _barWidth,
                        focus: focus,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 6),
              Text(dayLabel,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.text : AppColors.textHint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar(
      {required this.day,
      required this.height,
      required this.width,
      required this.focus});

  final DaySpend day;
  final double height;
  final double width;
  final ExpenseCategory? focus;

  /// 쌓인 분류 사이의 흰 틈.
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    // 쓰지 않은 날도 날짜가 비어 보이지 않게 낮은 회색 받침을 둔다.
    if (height <= 0) {
      return Container(
        width: width,
        height: 3,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    final parts = [
      for (final c in ExpenseCategory.values)
        if ((day.byCategory[c] ?? 0) > 0) (category: c, krw: day.byCategory[c]!),
    ];
    // 너무 낮은 막대는 틈을 두면 색이 보이지 않아서 붙여 그린다.
    final gap = height - _gap * (parts.length - 1) >= parts.length * 3
        ? _gap
        : 0.0;
    final room = height - gap * (parts.length - 1);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          verticalDirection: VerticalDirection.up,
          children: [
            for (final (i, p) in parts.indexed) ...[
              if (i > 0) SizedBox(height: gap),
              Container(
                height: room * p.krw / day.krw,
                color: focus == null || focus == p.category
                    ? p.category.color
                    : p.category.color.withValues(alpha: 0.18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
