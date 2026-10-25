import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

const _tabular = [FontFeature.tabularFigures()];

/// 개수를 하나씩 늘리고 줄인다. 0이면 + 버튼만 보인다. [max]까지만 늘릴 수 있다.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.count,
    required this.max,
    required this.onChanged,
    required this.name,
  });

  final int count;
  final int max;
  final ValueChanged<int> onChanged;

  /// 버튼 설명에 쓸 이름 ("민수 하나 더").
  final String name;

  @override
  Widget build(BuildContext context) {
    void add() {
      HapticFeedback.selectionClick();
      onChanged(count + 1);
    }

    final canAdd = count < max;
    if (count == 0) {
      return IconButton.filledTonal(
        tooltip: '$name 하나 담기',
        onPressed: canAdd ? add : null,
        icon: const Icon(Icons.add_rounded),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '$name 하나 빼기',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(count - 1),
            icon: const Icon(Icons.remove_rounded,
                size: 20, color: AppColors.primaryDeep),
          ),
          Text('$count',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDeep,
                  fontFeatures: _tabular)),
          IconButton(
            tooltip: '$name 하나 더',
            visualDensity: VisualDensity.compact,
            onPressed: canAdd ? add : null,
            icon: Icon(Icons.add_rounded,
                size: 20,
                color: canAdd ? AppColors.primaryDeep : AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
