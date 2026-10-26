import 'package:flutter/material.dart';

import '../../domain/receipt.dart';
import '../../../../core/theme/app_icons.dart';

extension ExpenseCategoryStyle on ExpenseCategory {
  IconData get icon => switch (this) {
        ExpenseCategory.food => AppIcons.food,
        ExpenseCategory.cafe => AppIcons.cafe,
        ExpenseCategory.shopping => AppIcons.shopping,
        ExpenseCategory.transport => AppIcons.transport,
        ExpenseCategory.lodging => AppIcons.lodging,
        ExpenseCategory.activity => AppIcons.activity,
        ExpenseCategory.other => AppIcons.receiptFill,
      };

  Color get color => switch (this) {
        ExpenseCategory.food => const Color(0xFFFF6B4A),
        ExpenseCategory.cafe => const Color(0xFFB07A4F),
        ExpenseCategory.shopping => const Color(0xFFE94E9B),
        ExpenseCategory.transport => const Color(0xFF3182F6),
        ExpenseCategory.lodging => const Color(0xFF7B61FF),
        ExpenseCategory.activity => const Color(0xFF00B386),
        ExpenseCategory.other => const Color(0xFF8B95A1),
      };
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.size = 44});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(category.icon, color: category.color, size: size * 0.5),
    );
  }
}
