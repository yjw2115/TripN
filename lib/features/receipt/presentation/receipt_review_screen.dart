import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/receipt.dart';
import '../domain/receipt_validator.dart';
import 'widgets/category_badge.dart';
import 'widgets/edit_sheets.dart';

/// 확인 화면으로 넘길 값.
class ReviewArgs {
  const ReviewArgs({
    required this.receipt,
    this.warnings = const [],
    this.receiptCount = 1,
    this.imagePaths = const [],
    this.expenseId,
  });

  final Receipt receipt;
  final List<String> warnings;
  final int receiptCount;
  final List<String> imagePaths;

  /// 이미 저장된 지출을 고칠 때만 있다.
  final String? expenseId;
}

/// 인식 결과를 확인하고 고친 뒤 저장한다. 자동 저장하지 않는다.
class ReceiptReviewScreen extends ConsumerStatefulWidget {
  const ReceiptReviewScreen({super.key, required this.args});

  final ReviewArgs args;

  @override
  ConsumerState<ReceiptReviewScreen> createState() =>
      _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  late Receipt _receipt = widget.args.receipt;
  bool _saving = false;

  Currency get _currency => _receipt.currency;

  String _money(int minor) => formatMoney(minor, _currency);

  void _update(Receipt next) => setState(() => _receipt = next);

  Future<void> _editMerchant() async {
    final name = await showTextSheet(context,
        title: '어디서 썼나요?', initial: _receipt.merchantName, hint: '가게 이름');
    if (name != null) _update(_receipt.copyWith(merchantName: name));
  }

  Future<void> _editTotal() async {
    final total = await showAmountSheet(context,
        title: '총 결제 금액', initialMinor: _receipt.totalMinor, currency: _currency);
    if (total != null) _update(_receipt.copyWith(totalMinor: total));
  }

  Future<void> _editDate() async {
    final current = _receipt.paidAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    _update(_receipt.copyWith(
        paidAt: DateTime(date.year, date.month, date.day,
            time?.hour ?? current.hour, time?.minute ?? current.minute)));
  }

  Future<void> _editCategory() async {
    final picked = await showAppSheet<ExpenseCategory>(
      context,
      (context) => SheetScaffold(
        title: '어떤 지출인가요?',
        primaryLabel: '닫기',
        onPrimary: () => Navigator.pop(context),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in ExpenseCategory.values)
              ChoiceChip(
                avatar: Icon(c.icon, size: 18, color: c.color),
                label: Text(c.label),
                selected: c == _receipt.category,
                onSelected: (_) => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _update(_receipt.copyWith(category: picked));
  }

  /// 통화를 잘못 인식했을 때 고친다. 영수증에 보이는 숫자는 그대로 둔다.
  Future<void> _editCurrency() async {
    final picked = await showAppSheet<Currency>(
      context,
      (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            for (final c in Currency.all)
              ListTile(
                title: Text('${c.nameKo} · ${c.code}'),
                trailing: c == _currency
                    ? const Icon(Icons.check_rounded, color: AppColors.primaryDeep)
                    : Text(c.symbol,
                        style: const TextStyle(color: AppColors.textHint)),
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _currency) return;
    int convert(int minor) => picked.toMinor(_currency.toMajor(minor));
    int? convertNullable(int? minor) => minor == null ? null : convert(minor);
    _update(_receipt.copyWith(
      currency: picked,
      items: [
        for (final i in _receipt.items)
          i.copyWith(
            amountMinor: convert(i.amountMinor),
            discountMinor: convert(i.discountMinor),
            unitPriceMinor: convertNullable(i.unitPriceMinor),
          ),
      ],
      taxMinor: convert(_receipt.taxMinor),
      serviceChargeMinor: convert(_receipt.serviceChargeMinor),
      tipMinor: convert(_receipt.tipMinor),
      discountMinor: convert(_receipt.discountMinor),
      totalMinor: convert(_receipt.totalMinor),
    ));
  }

  Future<void> _editItem(ReceiptItem item, {bool isNew = false}) async {
    final result = await showItemSheet(context,
        item: item, currency: _currency, isNew: isNew);
    if (result == null) return;
    final items = [..._receipt.items];
    final index = items.indexWhere((i) => i.id == item.id);
    if (result.deleted) {
      items.removeAt(index);
    } else if (index < 0) {
      items.add(result.item!);
    } else {
      items[index] = result.item!;
    }
    _update(_receipt.copyWith(items: items));
  }

  ReceiptItem _newItem({String nameKo = '', int amountMinor = 0}) => ReceiptItem(
        id: 'n${DateTime.now().microsecondsSinceEpoch}',
        name: nameKo,
        nameKo: nameKo,
        amountMinor: amountMinor,
      );

  Future<void> _editCharge(String title, int value, Receipt Function(int) apply) async {
    final next = await showAmountSheet(context,
        title: title, initialMinor: value, currency: _currency);
    if (next != null) _update(apply(next));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      final trip = await ref.read(currentTripProvider.future);
      await ref.read(expenseRepositoryProvider).saveReceipt(
            tripId: trip.id,
            uid: user.uid,
            receipt: _receipt,
            expenseId: widget.args.expenseId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('지출을 저장했어요')));
      context.go('/');
    } catch (e) {
      debugPrint('Save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장하지 못했어요. 잠시 후 다시 시도해 주세요.')));
    }
  }

  void _openPhotos() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewer(paths: widget.args.imagePaths),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final check = checkReceipt(_receipt);
    final args = widget.args;
    return Scaffold(
      appBar: AppBar(
        title: Text(args.expenseId == null ? '영수증 확인' : '지출 수정'),
        actions: [
          if (args.imagePaths.isNotEmpty)
            IconButton(
              tooltip: '사진 보기',
              onPressed: _openPhotos,
              icon: const Icon(Icons.image_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _HeaderCard(
            receipt: _receipt,
            money: _money,
            onMerchant: _editMerchant,
            onCategory: _editCategory,
            onDate: _editDate,
            onTotal: _editTotal,
            onCurrency: _editCurrency,
          ),
          const SizedBox(height: 12),
          if (args.receiptCount > 1) ...[
            _Banner.warning(
              title: '영수증이 ${args.receiptCount}장 찍혔어요',
              body: '그중 한 장만 정리했어요. 한 장씩 찍으면 더 정확해요.',
            ),
            const SizedBox(height: 12),
          ],
          _CheckBanner(
            check: check,
            money: _money,
            onAddDifference: () => _update(_receipt.copyWith(items: [
              ..._receipt.items,
              _newItem(nameKo: '기타', amountMinor: check.differenceMinor),
            ])),
            onUseComputedTotal: () => _update(
                _receipt.copyWith(totalMinor: _receipt.computedTotalMinor)),
          ),
          for (final w in args.warnings) ...[
            const SizedBox(height: 8),
            _Banner.info(body: w),
          ],
          const SizedBox(height: 12),
          _Card(
            title: '품목 ${_receipt.items.length}개',
            trailing: TextButton.icon(
              onPressed: () => _editItem(_newItem(), isNew: true),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('추가'),
            ),
            children: [
              if (_receipt.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('품목이 없어요',
                        style: TextStyle(color: AppColors.textHint)),
                  ),
                ),
              for (final item in _receipt.items)
                _ItemRow(
                  item: item,
                  money: _money,
                  currency: _currency,
                  hasMismatch: check.mismatchedItemIds.contains(item.id),
                  onTap: () => _editItem(item),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Card(
            title: '세금 · 추가 금액',
            children: [
              _ChargeRow(
                label: _receipt.taxIncluded ? '세금 (가격에 포함)' : '세금 (별도)',
                value: _receipt.taxMinor,
                money: _money,
                onTap: () => _editCharge('세금', _receipt.taxMinor,
                    (v) => _receipt.copyWith(taxMinor: v)),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('세금이 가격에 포함돼 있어요',
                    style: TextStyle(fontSize: 14, color: AppColors.textSub)),
                value: _receipt.taxIncluded,
                activeTrackColor: AppColors.primary,
                onChanged: (v) => _update(_receipt.copyWith(taxIncluded: v)),
              ),
              _ChargeRow(
                label: '봉사료',
                value: _receipt.serviceChargeMinor,
                money: _money,
                onTap: () => _editCharge('봉사료', _receipt.serviceChargeMinor,
                    (v) => _receipt.copyWith(serviceChargeMinor: v)),
              ),
              _ChargeRow(
                label: '팁',
                value: _receipt.tipMinor,
                money: _money,
                onTap: () => _editCharge('팁', _receipt.tipMinor,
                    (v) => _receipt.copyWith(tipMinor: v)),
              ),
              _ChargeRow(
                label: '전체 할인',
                value: _receipt.discountMinor,
                money: _money,
                negative: true,
                onTap: () => _editCharge('전체 할인', _receipt.discountMinor,
                    (v) => _receipt.copyWith(discountMinor: v)),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _saving || _receipt.totalMinor <= 0 ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.onPrimary))
                : Text(_receipt.totalMinor <= 0
                    ? '총 결제 금액을 입력해 주세요'
                    : '${_money(_receipt.totalMinor)} 저장하기'),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({this.title, this.trailing, required this.children});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Text(title!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.receipt,
    required this.money,
    required this.onMerchant,
    required this.onCategory,
    required this.onDate,
    required this.onTotal,
    required this.onCurrency,
  });

  final Receipt receipt;
  final String Function(int) money;
  final VoidCallback onMerchant;
  final VoidCallback onCategory;
  final VoidCallback onDate;
  final VoidCallback onTotal;
  final VoidCallback onCurrency;

  @override
  Widget build(BuildContext context) {
    final paidAt = receipt.paidAt;
    return _Card(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: onCategory,
              customBorder: const CircleBorder(),
              child: CategoryBadge(receipt.category),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: onMerchant,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.merchantName.isEmpty
                          ? '가게 이름 입력'
                          : receipt.merchantName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: receipt.merchantName.isEmpty
                            ? AppColors.textHint
                            : AppColors.text,
                      ),
                    ),
                    Text(receipt.category.label,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textHint)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: onTotal,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('총 결제 금액',
                  style: TextStyle(fontSize: 14, color: AppColors.textSub)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(receipt.totalMinor),
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Pill(
              icon: Icons.payments_outlined,
              label: '${receipt.currency.nameKo} ${receipt.currency.code}',
              onTap: onCurrency,
            ),
            const SizedBox(width: 8),
            _Pill(
              icon: Icons.schedule_rounded,
              label: paidAt == null
                  ? '날짜 입력'
                  : DateFormat('M월 d일 HH:mm', 'ko').format(paidAt),
              onTap: onDate,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.textSub),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSub)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner.warning({required this.title, required this.body})
      : _color = AppColors.warning,
        _background = AppColors.warningLight,
        _icon = Icons.error_outline_rounded,
        actions = const [];

  const _Banner.success({required this.title})
      : body = null,
        _color = AppColors.success,
        _background = AppColors.successLight,
        _icon = Icons.check_circle_rounded,
        actions = const [];

  const _Banner.info({required this.body})
      : title = null,
        _color = AppColors.textSub,
        _background = AppColors.surface,
        _icon = Icons.info_outline_rounded,
        actions = const [];

  const _Banner.mismatch({
    required this.title,
    required this.body,
    required this.actions,
  })  : _color = AppColors.warning,
        _background = AppColors.warningLight,
        _icon = Icons.error_outline_rounded;

  final String? title;
  final String? body;
  final List<Widget> actions;
  final Color _color;
  final Color _background;
  final IconData _icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, color: _color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title!,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _color == AppColors.textSub
                                  ? AppColors.text
                                  : _color)),
                    if (body != null) ...[
                      if (title != null) const SizedBox(height: 2),
                      Text(body!,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textSub)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 4, children: actions),
          ],
        ],
      ),
    );
  }
}

class _CheckBanner extends StatelessWidget {
  const _CheckBanner({
    required this.check,
    required this.money,
    required this.onAddDifference,
    required this.onUseComputedTotal,
  });

  final ReceiptCheck check;
  final String Function(int) money;
  final VoidCallback onAddDifference;
  final VoidCallback onUseComputedTotal;

  @override
  Widget build(BuildContext context) {
    if (check.totalMatches) {
      return _Banner.success(
        title: check.mismatchedItemIds.isEmpty
            ? '품목 합계가 총액과 맞아요'
            : '총액은 맞지만 수량 × 단가가 다른 품목이 있어요',
      );
    }
    final diff = check.differenceMinor;
    return _Banner.mismatch(
      title: diff > 0
          ? '품목 합계가 총액보다 ${money(diff)} 적어요'
          : '품목 합계가 총액보다 ${money(-diff)} 많아요',
      body: '영수증 사진과 비교해서 빠지거나 잘못 읽힌 품목이 없는지 확인해 주세요.',
      actions: [
        if (diff > 0)
          TextButton(
              onPressed: onAddDifference, child: const Text('차액을 기타로 추가')),
        TextButton(
            onPressed: onUseComputedTotal,
            child: const Text('총액을 품목 합계로 바꾸기')),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.money,
    required this.currency,
    required this.hasMismatch,
    required this.onTap,
  });

  final ReceiptItem item;
  final String Function(int) money;
  final Currency currency;
  final bool hasMismatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showOriginal = item.name.isNotEmpty && item.name != item.displayName;
    final quantity = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toInt().toString()
        : item.quantity.toString();
    final detail = [
      if (showOriginal) item.name,
      if (item.unitPriceMinor != null && item.quantity != 1)
        '$quantity × ${money(item.unitPriceMinor!)}'
      else if (item.quantity != 1)
        '$quantity개',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName.isEmpty ? '이름 없음' : item.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  if (detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textHint)),
                    ),
                  if (hasMismatch)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('수량 × 단가가 금액과 달라요',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.warning)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(item.netMinor),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (item.discountMinor > 0)
                  Text(
                    '${money(item.amountMinor)} − ${money(item.discountMinor)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.primaryDeep),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  const _ChargeRow({
    required this.label,
    required this.value,
    required this.money,
    required this.onTap,
    this.negative = false,
  });

  final String label;
  final int value;
  final String Function(int) money;
  final VoidCallback onTap;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 15, color: AppColors.textSub)),
            const Spacer(),
            Text(
              value == 0 ? '없음' : '${negative ? '−' : ''}${money(value)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: value == 0 ? AppColors.textHint : AppColors.text,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(paths.length > 1 ? '사진 ${paths.length}장' : '영수증 사진',
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView(
        children: [
          for (final path in paths)
            InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(File(path))),
            ),
        ],
      ),
    );
  }
}
