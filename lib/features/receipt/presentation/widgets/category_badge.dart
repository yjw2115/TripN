import 'package:flutter/material.dart';

import '../../domain/receipt.dart';

extension ExpenseCategoryStyle on ExpenseCategory {
  IconData get icon => switch (this) {
        ExpenseCategory.food => Icons.restaurant_rounded,
        ExpenseCategory.cafe => Icons.local_cafe_rounded,
        ExpenseCategory.shopping => Icons.shopping_bag_rounded,
        ExpenseCategory.transport => Icons.directions_bus_rounded,
        ExpenseCategory.lodging => Icons.hotel_rounded,
        ExpenseCategory.activity => Icons.local_activity_rounded,
        ExpenseCategory.other => Icons.receipt_long_rounded,
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
