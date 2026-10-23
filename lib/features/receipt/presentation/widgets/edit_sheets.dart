import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/money/currency.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/receipt.dart';

/// 바텀시트 공통 틀: 제목 + 내용 + 하단 버튼.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            child,
            const SizedBox(height: 24),
            Row(
              children: [
                if (secondaryLabel != null) ...[
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.background,
                        foregroundColor: AppColors.textSub,
                      ),
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                      onPressed: onPrimary, child: Text(primaryLabel)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

TextInputFormatter _moneyFormatter(Currency currency) =>
    FilteringTextInputFormatter.allow(
        RegExp(currency.decimals == 0 ? r'[0-9]' : r'[0-9.]'));

/// 금액 하나를 고치는 시트. 저장하면 최소 단위 정수를 돌려준다.
Future<int?> showAmountSheet(
  BuildContext context, {
  required String title,
  required int initialMinor,
  required Currency currency,
}) {
  final controller = TextEditingController(
      text: initialMinor == 0 ? '' : formatMoneyPlain(initialMinor, currency));
  return showAppSheet<int>(
    context,
    (context) => SheetScaffold(
      title: title,
      primaryLabel: '확인',
      onPrimary: () => Navigator.pop(
          context, parseMoneyInput(controller.text, currency) ?? 0),
      child: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
            decimal: currency.decimals > 0),
        inputFormatters: [_moneyFormatter(currency)],
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: '0',
          suffixText: currency.code,
        ),
      ),
    ),
  );
}

/// 가게 이름 같은 짧은 글을 고치는 시트.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String initial,
  String hint = '',
}) {
  final controller = TextEditingController(text: initial);
  return showAppSheet<String>(
    context,
    (context) => SheetScaffold(
      title: title,
      primaryLabel: '확인',
      onPrimary: () => Navigator.pop(context, controller.text.trim()),
      child: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: InputDecoration(hintText: hint),
      ),
    ),
  );
}

/// 품목 편집 결과. [deleted]면 품목을 지운다.
class ItemEditResult {
  const ItemEditResult.saved(ReceiptItem this.item) : deleted = false;
  const ItemEditResult.deleted()
      : item = null,
        deleted = true;

  final ReceiptItem? item;
  final bool deleted;
}

Future<ItemEditResult?> showItemSheet(
  BuildContext context, {
  required ReceiptItem item,
  required Currency currency,
  required bool isNew,
}) {
  return showAppSheet<ItemEditResult>(
    context,
    (context) => _ItemSheet(item: item, currency: currency, isNew: isNew),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet(
      {required this.item, required this.currency, required this.isNew});

  final ReceiptItem item;
  final Currency currency;
  final bool isNew;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _nameKo = TextEditingController(text: widget.item.nameKo);
  late final _name = TextEditingController(text: widget.item.name);
  late final _quantity = TextEditingController(
      text: _formatQuantity(widget.item.quantity));
  late final _unitPrice = TextEditingController(
      text: widget.item.unitPriceMinor == null
          ? ''
          : formatMoneyPlain(widget.item.unitPriceMinor!, widget.currency));
  late final _amount = TextEditingController(
      text: widget.item.amountMinor == 0
          ? ''
          : formatMoneyPlain(widget.item.amountMinor, widget.currency));
  late final _discount = TextEditingController(
      text: widget.item.discountMinor == 0
          ? ''
          : formatMoneyPlain(widget.item.discountMinor, widget.currency));

  static String _formatQuantity(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  @override
  void dispose() {
    for (final c in [_nameKo, _name, _quantity, _unitPrice, _amount, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 수량이나 단가를 바꾸면 금액을 다시 계산한다.
  void _recalculate() {
    final quantity = double.tryParse(_quantity.text);
    final unit = parseMoneyInput(_unitPrice.text, widget.currency);
    if (quantity == null || unit == null) return;
    _amount.text =
        formatMoneyPlain((unit * quantity).round(), widget.currency);
  }

  void _save() {
    final c = widget.currency;
    final nameKo = _nameKo.text.trim();
    final name = _name.text.trim();
    Navigator.pop(
      context,
      ItemEditResult.saved(widget.item.copyWith(
        nameKo: nameKo,
        name: name.isEmpty ? nameKo : name,
        quantity: double.tryParse(_quantity.text) ?? 1,
        unitPriceMinor: parseMoneyInput(_unitPrice.text, c),
        clearUnitPrice: parseMoneyInput(_unitPrice.text, c) == null,
        amountMinor: parseMoneyInput(_amount.text, c) ?? 0,
        discountMinor: parseMoneyInput(_discount.text, c) ?? 0,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.currency;
    final money = TextInputType.numberWithOptions(decimal: c.decimals > 0);
    return SheetScaffold(
      title: widget.isNew ? '품목 추가' : '품목 수정',
      primaryLabel: '저장',
      onPrimary: _save,
      secondaryLabel: widget.isNew ? null : '삭제',
      onSecondary: () =>
          Navigator.pop(context, const ItemEditResult.deleted()),
      child: Column(
        children: [
          _LabeledField(
            label: '이름',
            child: TextField(
              controller: _nameKo,
              autofocus: widget.isNew,
              decoration: const InputDecoration(hintText: '예) 라멘'),
            ),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: '영수증에 적힌 이름',
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: '예) ラーメン'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: '수량',
                  child: TextField(
                    controller: _quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _recalculate(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _LabeledField(
                  label: '단가',
                  child: TextField(
                    controller: _unitPrice,
                    keyboardType: money,
                    inputFormatters: [_moneyFormatter(c)],
                    onChanged: (_) => _recalculate(),
                    decoration: InputDecoration(suffixText: c.code),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: '금액',
                  child: TextField(
                    controller: _amount,
                    keyboardType: money,
                    inputFormatters: [_moneyFormatter(c)],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(suffixText: c.code),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LabeledField(
                  label: '할인',
                  child: TextField(
                    controller: _discount,
                    keyboardType: money,
                    inputFormatters: [_moneyFormatter(c)],
                    decoration:
                        InputDecoration(hintText: '0', suffixText: c.code),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
