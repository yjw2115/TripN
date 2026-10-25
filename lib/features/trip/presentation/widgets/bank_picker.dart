import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../receipt/presentation/widgets/edit_sheets.dart';
import '../../domain/bank.dart';

/// 은행 아이콘. 아이콘이 없는 은행이나 직접 적은 은행은 이름 첫 글자로 그린다.
class BankIcon extends StatelessWidget {
  const BankIcon(this.bankName, {super.key, this.size = 36});

  /// 저장된 은행 이름 ([Bank.find]로 찾는다).
  final String bankName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bank = Bank.find(bankName);
    final radius = BorderRadius.circular(size * 0.24);
    // 흰 바탕 아이콘도 흰 시트 위에서 모양이 보이게 옅은 테두리를 둔다.
    final edge = BoxDecoration(
      borderRadius: radius,
      border: Border.all(color: const Color(0x14000000)),
    );
    final asset = bank?.asset;
    if (asset != null) {
      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: radius),
        foregroundDecoration: edge,
        child: Image.asset(asset, fit: BoxFit.cover),
      );
    }
    final name = bank?.label ?? bankName.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: edge.copyWith(color: AppColors.surface),
      child: Text(name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: AppColors.textSub)),
    );
  }
}

/// 돈 받을 은행을 고른다. 고른 은행의 이름(직접 입력이면 적은 이름)을 돌려준다.
Future<String?> showBankPicker(BuildContext context, {String selected = ''}) =>
    showAppSheet<String>(context, (context) => _BankPicker(selected: selected));

class _BankPicker extends StatelessWidget {
  const _BankPicker({required this.selected});

  final String selected;

  Future<void> _typeName(BuildContext context, bool typedBefore) async {
    final name = await showTextSheet(context,
        title: '은행 이름',
        initial: typedBefore ? selected : '',
        hint: '예) 토스증권');
    if (name != null && name.isNotEmpty && context.mounted) {
      Navigator.pop(context, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = Bank.find(selected);
    final typedBefore = current == null && selected.trim().isNotEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
            sliver: SliverToBoxAdapter(
              child: Text('어느 은행 계좌인가요?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverGrid.count(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                for (final bank in Bank.all)
                  _BankTile(
                    label: bank.label,
                    icon: BankIcon(bank.name),
                    selected: identical(bank, current),
                    onTap: () => Navigator.pop(context, bank.name),
                  ),
                _BankTile(
                  label: typedBefore ? selected : '직접 입력',
                  icon: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.edit_outlined, color: AppColors.textSub),
                  ),
                  selected: typedBefore,
                  onTap: () => _typeName(context, typedBefore),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: selected
          ? const BorderSide(color: AppColors.primaryDeep, width: 1.5)
          : BorderSide.none,
    );
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.background,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
