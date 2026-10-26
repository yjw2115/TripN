import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/money/currency.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../trip/domain/trip.dart';
import '../../../trip/presentation/widgets/trip_widgets.dart';
import '../../domain/receipt.dart';
import 'count_stepper.dart';
import '../../../../core/ui/controls.dart';

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
            // 내용이 길면(동행자가 많은 품목 시트 등) 버튼은 두고 내용만 스크롤한다.
            Flexible(child: SingleChildScrollView(child: child)),
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

/// 날짜와 시각을 한 번에 고른다 (머티리얼 달력·시계 대신 iOS식 휠).
Future<DateTime?> showDateTimeSheet(BuildContext context,
    {required String title, required DateTime initial}) {
  final latest = DateTime.now().add(const Duration(days: 365));
  final start = initial.isAfter(latest) ? latest : initial;
  var picked = start;
  return showAppSheet<DateTime>(
    context,
    (context) => SheetScaffold(
      title: title,
      primaryLabel: '확인',
      onPrimary: () => Navigator.pop(context, picked),
      child: SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.dateAndTime,
          initialDateTime: start,
          minimumDate: DateTime(2000),
          maximumDate: latest,
          use24hFormat: true,
          onDateTimeChanged: (d) => picked = d,
        ),
      ),
    ),
  );
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

/// 영수증에 적힌 그대로 칠 수 있게 숫자와 "." "," 를 모두 받는다. 해석은 [parseMoneyInput]이 통화를 보고 한다.
final _moneyFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
const _moneyKeyboard = TextInputType.numberWithOptions(decimal: true);

/// 입력한 숫자를 앱이 어떻게 읽었는지 바로 보여준다 (예: "130.000" → 130,000동).
class _ParsedAmount extends StatelessWidget {
  const _ParsedAmount({required this.controller, required this.currency});

  final TextEditingController controller;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final minor = parseMoneyInput(value.text, currency);
        final hint = currency.decimals == 0
            ? '점(.)과 쉼표(,)는 천 단위로 읽어요'
            : '소수점은 점(.)이나 쉼표(,)로 쳐도 돼요';
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            minor == null ? hint : '${formatMoney(minor, currency)}으로 저장돼요 · $hint',
            style: const TextStyle(fontSize: 13, color: AppColors.textHint),
          ),
        );
      },
    );
  }
}

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: _moneyKeyboard,
            inputFormatters: [_moneyFormatter],
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0',
              suffixText: currency.code,
            ),
          ),
          _ParsedAmount(controller: controller, currency: currency),
        ],
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
  int? maxLength,
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
        maxLength: maxLength,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: InputDecoration(hintText: hint, counterText: ''),
        onSubmitted: (text) => Navigator.pop(context, text.trim()),
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

/// [together]는 이 지출을 함께 쓴 멤버. 두 명 이상이면 품목을 같이 먹은 사람을 고를 수 있다.
Future<ItemEditResult?> showItemSheet(
  BuildContext context, {
  required ReceiptItem item,
  required Currency currency,
  required bool isNew,
  List<Member> together = const [],
}) {
  return showAppSheet<ItemEditResult>(
    context,
    (context) => _ItemSheet(
        item: item, currency: currency, isNew: isNew, together: together),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.item,
    required this.currency,
    required this.isNew,
    required this.together,
  });

  final ReceiptItem item;
  final Currency currency;
  final bool isNew;
  final List<Member> together;

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

  /// 비어 있으면 함께 쓴 사람 모두.
  late final Set<String> _who = {...widget.item.participantIds};

  /// 각자 가져간 개수. 나머지 개수는 [_who]끼리 나눈다.
  late final Map<String, int> _taken = {
    for (final e in widget.item.takenBy.entries)
      if (widget.together.any((m) => m.id == e.key)) e.key: e.value,
  };

  int get _units => ReceiptItem.unitsOf(_parseQuantity(_quantity.text) ?? 1);

  int get _takenCount => _taken.values.fold(0, (sum, n) => sum + n);

  static double? _parseQuantity(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

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
    final quantity = _parseQuantity(_quantity.text);
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
        quantity: _parseQuantity(_quantity.text) ?? 1,
        unitPriceMinor: parseMoneyInput(_unitPrice.text, c),
        clearUnitPrice: parseMoneyInput(_unitPrice.text, c) == null,
        amountMinor: parseMoneyInput(_amount.text, c) ?? 0,
        discountMinor: parseMoneyInput(_discount.text, c) ?? 0,
        // 함께 쓴 사람을 전부 고른 것은 "모두"와 같다.
        participantIds: widget.together.every((m) => _who.contains(m.id))
            ? const []
            : [
                for (final m in widget.together)
                  if (_who.contains(m.id)) m.id,
              ],
        takenBy: {
          for (final m in widget.together)
            if ((_taken[m.id] ?? 0) > 0) m.id: _taken[m.id]!,
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.currency;
    const money = _moneyKeyboard;
    final units = _units;
    final shared = units > _takenCount ? units - _takenCount : 0;
    // 수량을 줄여서 고른 개수가 더 많아지면 저장하기 전에 고치게 한다.
    final overTaken = _takenCount > units;
    return SheetScaffold(
      title: widget.isNew ? '품목 추가' : '품목 수정',
      primaryLabel: overTaken ? '수량보다 많이 골랐어요' : '저장',
      onPrimary: overTaken ? null : _save,
      secondaryLabel: widget.isNew ? null : '삭제',
      onSecondary: () =>
          Navigator.pop(context, const ItemEditResult.deleted()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    onChanged: (_) => setState(_recalculate),
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
                    inputFormatters: [_moneyFormatter],
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
                    inputFormatters: [_moneyFormatter],
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
                    inputFormatters: [_moneyFormatter],
                    decoration:
                        InputDecoration(hintText: '0', suffixText: c.code),
                  ),
                ),
              ),
            ],
          ),
          if (widget.together.length > 1 &&
              (units > 1 || _taken.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _LabeledField(
              label: '각자 몫 (고른 개수만큼 각자 내요)',
              child: Column(
                children: [
                  for (final m in widget.together)
                    SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          MemberAvatar(m, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(m.name,
                                style: const TextStyle(fontSize: 16)),
                          ),
                          CountStepper(
                            count: _taken[m.id] ?? 0,
                            max: (_taken[m.id] ?? 0) + shared,
                            name: m.name,
                            onChanged: (n) => setState(() =>
                                n > 0 ? _taken[m.id] = n : _taken.remove(m.id)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          // 모두 각자 가져갔으면 함께 나눌 게 없다.
          if (widget.together.length > 1 && (_taken.isEmpty || shared > 0)) ...[
            const SizedBox(height: 12),
            _LabeledField(
              label: _taken.isEmpty
                  ? '같이 먹은 사람 (고르지 않으면 모두)'
                  : '나머지 $shared개를 같이 먹은 사람 (고르지 않으면 모두)',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppChip(
                    label: '모두',
                    selected: _who.isEmpty,
                    onTap: () => setState(_who.clear),
                  ),
                  for (final m in widget.together)
                    AppChip(
                      label: m.name,
                      selected: _who.contains(m.id),
                      onTap: () => setState(() => _who.contains(m.id)
                          ? _who.remove(m.id)
                          : _who.add(m.id)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
