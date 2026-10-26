import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/receipt_review_screen.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/menu.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/controls.dart';
import 'menu_actions.dart';

/// 메뉴 화면으로 넘길 값. 방금 찍은 메뉴판이면 저장이 끝나기 전에도 바로 보여준다.
class MenuScreenArgs {
  const MenuScreenArgs({required this.menu, this.warnings = const []});

  final Menu menu;
  final List<String> warnings;
}

const _tabular = [FontFeature.tabularFigures()];

/// 번역된 메뉴판에서 메뉴를 고르고, 미리 보는 영수증으로 합계를 본 뒤 지출로 기록한다.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, required this.menuId, this.args});

  final String menuId;
  final MenuScreenArgs? args;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final Map<String, int> _quantities = {};
  int _tipMinor = 0;
  late List<String> _warnings = widget.args?.warnings ?? const [];

  void _setQuantity(String itemId, int quantity) =>
      setState(() => _quantities[itemId] = quantity.clamp(0, 99));

  void _save(Menu menu) {
    final tripId = ref.read(currentTripProvider).value?.id;
    if (tripId == null) return;
    reportWriteErrors(context, ref.read(menuRepositoryProvider).update(tripId, menu));
  }

  Future<void> _renameStore(Menu menu) async {
    final name = await showTextSheet(context,
        title: '가게 이름', initial: menu.storeName, hint: '예) 이치란 시부야점', maxLength: 40);
    if (name == null || name == menu.storeName || !mounted) return;
    _save(menu.copyWith(storeName: name));
  }

  Future<void> _editCharges(Menu menu) async {
    final next = await showAppSheet<Menu>(
        context, (context) => _ChargesSheet(menu: menu));
    if (next != null && mounted) _save(next);
  }

  Future<void> _editItem(Menu menu, MenuItem? item) async {
    final result = await showAppSheet<_ItemEdit>(
        context, (context) => _ItemSheet(item: item, currency: menu.currency));
    if (result == null || !mounted) return;
    final items = [...menu.items];
    if (result.deleted) {
      items.removeWhere((i) => i.id == item!.id);
      setState(() => _quantities.remove(item!.id));
    } else if (item == null) {
      items.add(MenuItem(
        id: 'u${DateTime.now().microsecondsSinceEpoch}',
        name: result.name.isEmpty ? result.nameKo : result.name,
        nameKo: result.nameKo,
        priceMinor: result.priceMinor,
        section: '직접 추가',
      ));
    } else {
      final index = items.indexWhere((i) => i.id == item.id);
      items[index] = item.copyWith(
          name: result.name.isEmpty ? result.nameKo : result.name,
          nameKo: result.nameKo,
          priceMinor: result.priceMinor);
    }
    _save(menu.copyWith(items: items));
  }

  Future<void> _openPreview(Menu menu, FixedRate? rate) async {
    final tip = await showAppSheet<int>(
      context,
      (context) => _PreviewSheet(
        menu: menu,
        quantities: Map.of(_quantities),
        initialTipMinor: _tipMinor,
        rate: rate,
      ),
    );
    if (tip == null || !mounted) return;
    setState(() => _tipMinor = tip);
    final preview = previewOrder(menu, _quantities, tipMinor: tip);
    context.push('/review',
        extra: ReviewArgs(
          receipt: preview.toReceipt(),
          source: 'menu',
          warnings: const ['메뉴판 가격으로 계산했어요. 실제로 낸 금액이 다르면 총액을 고쳐 주세요.'],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuProvider(widget.menuId));
    final menu = menuAsync.value ?? widget.args?.menu;
    if (menu == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: menuAsync.isLoading
              ? const AppSpinner()
              : const Text('메뉴판을 찾지 못했어요',
                  style: TextStyle(color: AppColors.textHint)),
        ),
      );
    }
    final rate = ref
        .watch(rateQuoteProvider(
            (menu.currency.code, rateDateKey(DateTime.now()))))
        .value;
    final preview = previewOrder(menu, _quantities, tipMinor: _tipMinor);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => _renameStore(menu),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(menu.storeName.isEmpty ? '메뉴판' : menu.storeName,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 4),
                const Icon(AppIcons.edit, size: 16, color: AppColors.textHint),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '메뉴판 지우기',
            icon: const Icon(AppIcons.trash, color: AppColors.danger),
            onPressed: () async {
              if (await confirmDeleteMenu(context, ref, menu) && context.mounted) {
                context.pop();
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _ChargesBar(menu: menu, rate: rate, onTap: () => _editCharges(menu)),
          for (final w in _warnings) ...[
            const SizedBox(height: 8),
            _WarningBanner(
              text: w,
              onClose: () => setState(
                  () => _warnings = [..._warnings]..remove(w)),
            ),
          ],
          for (final (section, items) in menu.sections) ...[
            if (section.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text(section,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSub)),
              )
            else
              const SizedBox(height: 12),
            SectionCard(children: [
              for (final item in items)
                _MenuItemRow(
                  item: item,
                  currency: menu.currency,
                  rate: rate,
                  quantity: _quantities[item.id] ?? 0,
                  onChanged: (q) => _setQuantity(item.id, q),
                  onEdit: () => _editItem(menu, item),
                ),
            ]),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => _editItem(menu, null),
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text('메뉴판에 없는 메뉴 추가'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: preview.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('메뉴를 고르면 합계를 미리 계산해 드려요',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: AppColors.textHint)),
                )
              : FilledButton(
                  onPressed: () => _openPreview(menu, rate),
                  child: Row(
                    children: [
                      Text('${preview.itemCount}개',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${formatMoney(preview.totalMinor, menu.currency)}'
                          '${rate == null || menu.currency == Currency.krw ? '' : ' · ≈ ${formatMoney(rate.toKrw(preview.totalMinor, menu.currency), Currency.krw)}'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFeatures: _tabular),
                        ),
                      ),
                      const Text('미리 보는 영수증'),
                      const Icon(AppIcons.chevronRight),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// 통화, 세금, 봉사료, 환율 기준. 누르면 세금·봉사료를 고친다.
class _ChargesBar extends StatelessWidget {
  const _ChargesBar({required this.menu, required this.rate, required this.onTap});

  final Menu menu;
  final FixedRate? rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labels = [
      '${menu.currency.nameKo} ${menu.currency.code}',
      menu.taxIncluded
          ? '세금 포함'
          : menu.taxRatePercent > 0
              ? '세금 별도 ${_percent(menu.taxRatePercent)}'
              : '세금 별도 (세율 입력 필요)',
      if (menu.serviceChargePercent > 0)
        '봉사료 ${_percent(menu.serviceChargePercent)}',
    ];
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(labels.join(' · '),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                    if (rate != null && menu.currency != Currency.krw)
                      Text(
                          '원화는 ${formatRate(rate!, menu.currency)} 기준이에요',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textHint)),
                  ],
                ),
              ),
              const Icon(AppIcons.adjust, size: 20, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

String _percent(double v) =>
    '${v == v.roundToDouble() ? v.toInt() : v}%';

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.info, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 14, color: AppColors.textSub)),
          ),
          IconButton(
            tooltip: '닫기',
            visualDensity: VisualDensity.compact,
            icon: const Icon(AppIcons.close, size: 18, color: AppColors.textHint),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({
    required this.item,
    required this.currency,
    required this.rate,
    required this.quantity,
    required this.onChanged,
    required this.onEdit,
  });

  final MenuItem item;
  final Currency currency;
  final FixedRate? rate;
  final int quantity;
  final ValueChanged<int> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final showOriginal = item.name.isNotEmpty && item.name != item.displayName;
    final hasPrice = item.priceMinor > 0;
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: quantity > 0 ? AppColors.primaryDeep : AppColors.text)),
                  if (showOriginal)
                    Text(item.name,
                        style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
                  if (item.descriptionKo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(item.descriptionKo,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                    ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: hasPrice ? formatMoney(item.priceMinor, currency) : '가격 없음',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: hasPrice ? AppColors.text : AppColors.warning),
                      ),
                      if (hasPrice && rate != null && currency != Currency.krw)
                        TextSpan(
                          text: '  ≈ ${formatMoney(rate!.toKrw(item.priceMinor, currency), Currency.krw)}',
                          style: const TextStyle(fontSize: 13, color: AppColors.textHint),
                        ),
                    ]),
                    style: const TextStyle(fontFeatures: _tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Stepper(quantity: quantity, onChanged: onChanged, name: item.displayName),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onChanged, required this.name});

  final int quantity;
  final ValueChanged<int> onChanged;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (quantity == 0) {
      return IconButton.filledTonal(
        tooltip: '$name 담기',
        onPressed: () {
          HapticFeedback.selectionClick();
          onChanged(1);
        },
        icon: const Icon(AppIcons.plus),
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
            tooltip: '$name 빼기',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(quantity - 1),
            icon: Icon(quantity == 1 ? AppIcons.trash : AppIcons.minus,
                size: 20, color: AppColors.primaryDeep),
          ),
          Text('$quantity',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDeep,
                  fontFeatures: _tabular)),
          IconButton(
            tooltip: '$name 더 담기',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged(quantity + 1);
            },
            icon: const Icon(AppIcons.plus, size: 20, color: AppColors.primaryDeep),
          ),
        ],
      ),
    );
  }
}

/// 미리 보는 영수증. 팁을 정하고 "이대로 기록하기"를 누르면 팁을 돌려준다.
class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({
    required this.menu,
    required this.quantities,
    required this.initialTipMinor,
    required this.rate,
  });

  final Menu menu;
  final Map<String, int> quantities;
  final int initialTipMinor;
  final FixedRate? rate;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  late int _tipMinor = widget.initialTipMinor;

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu;
    final c = menu.currency;
    final preview = previewOrder(menu, widget.quantities, tipMinor: _tipMinor);
    final suggestions = tipSuggestionsFor(menu.countryCode);
    String money(int minor) => formatMoney(minor, c);
    final rate = widget.rate;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              children: [
                const Text('미리 보는 영수증',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    '${menu.storeName.isEmpty ? '' : '${menu.storeName} · '}'
                    '${DateFormat('M월 d일 HH:mm', 'ko').format(DateTime.now())}',
                    style: const TextStyle(fontSize: 14, color: AppColors.textHint)),
                const SizedBox(height: 16),
                for (final line in preview.lines)
                  _ReceiptRow(
                    label: line.item.displayName,
                    detail: line.quantity > 1
                        ? '${money(line.item.priceMinor)} × ${line.quantity}'
                        : null,
                    value: money(line.amountMinor),
                  ),
                const _DashedDivider(),
                _ReceiptRow(label: '소계', value: money(preview.subtotalMinor)),
                if (menu.serviceChargePercent > 0)
                  _ReceiptRow(
                      label: '봉사료 ${_percent(menu.serviceChargePercent)}',
                      value: money(preview.serviceChargeMinor)),
                _ReceiptRow(
                  label: menu.taxIncluded
                      ? '세금 (가격에 포함)'
                      : '세금 ${_percent(menu.taxRatePercent)} (별도)',
                  value: menu.taxIncluded ? '포함' : money(preview.taxMinor),
                  muted: menu.taxIncluded,
                ),
                _TipRow(
                  tipMinor: _tipMinor,
                  money: money,
                  suggestions: suggestions,
                  subtotalMinor: preview.subtotalMinor,
                  onChanged: (v) => setState(() => _tipMinor = v),
                  onCustom: () async {
                    final v = await showAmountSheet(context,
                        title: '팁', initialMinor: _tipMinor, currency: c);
                    if (v != null) setState(() => _tipMinor = v);
                  },
                ),
                const _DashedDivider(),
                _ReceiptRow(
                    label: '합계', value: money(preview.totalMinor), bold: true),
                if (rate != null && c != Currency.krw)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '≈ ${formatMoney(rate.toKrw(preview.totalMinor, c), Currency.krw)} · ${formatRate(rate, c)}',
                      style: const TextStyle(fontSize: 14, color: AppColors.textSub),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  '실제 결제 금액과 다를 수 있어요. 기록한 뒤 영수증 확인 화면에서 결제한 사람과 같이 먹은 사람을 정할 수 있어요.',
                  style: TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.4),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _tipMinor),
                child: Text('${money(preview.totalMinor)} 이대로 기록하기'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.detail,
    this.bold = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final String? detail;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 20 : 15,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: muted ? AppColors.textHint : AppColors.text,
      fontFeatures: _tabular,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style.copyWith(fontFeatures: const [])),
                if (detail != null)
                  Text(detail!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textHint, fontFeatures: _tabular)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({
    required this.tipMinor,
    required this.money,
    required this.suggestions,
    required this.subtotalMinor,
    required this.onChanged,
    required this.onCustom,
  });

  final int tipMinor;
  final String Function(int) money;
  final List<int> suggestions;
  final int subtotalMinor;
  final ValueChanged<int> onChanged;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    int tipFor(int percent) => (subtotalMinor * percent / 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('팁', style: TextStyle(fontSize: 15))),
              TextButton(
                onPressed: onCustom,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(tipMinor == 0 ? '추가' : money(tipMinor),
                    style: const TextStyle(fontFeatures: _tabular)),
              ),
            ],
          ),
          if (suggestions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                AppChip(
                  label: '없음',
                  selected: tipMinor == 0,
                  onTap: () => onChanged(0),
                ),
                for (final p in suggestions)
                  AppChip(
                    label: '$p%',
                    selected: tipMinor != 0 && tipMinor == tipFor(p),
                    onTap: () => onChanged(tipFor(p)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dash = 6.0, gap = 4.0;
          final count = (constraints.maxWidth / (dash + gap)).floor();
          return Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                Container(width: dash, height: 1, color: AppColors.border),
                const SizedBox(width: gap),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 세금 포함 여부·세율·봉사료를 고친다. 저장하면 이 가게 메뉴판에 남는다.
class _ChargesSheet extends StatefulWidget {
  const _ChargesSheet({required this.menu});

  final Menu menu;

  @override
  State<_ChargesSheet> createState() => _ChargesSheetState();
}

class _ChargesSheetState extends State<_ChargesSheet> {
  late bool _included = widget.menu.taxIncluded;
  late final _taxRate = TextEditingController(
      text: widget.menu.taxRatePercent == 0 ? '' : _trim(widget.menu.taxRatePercent));
  late final _service = TextEditingController(
      text: widget.menu.serviceChargePercent == 0
          ? ''
          : _trim(widget.menu.serviceChargePercent));

  static String _trim(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  static double _parse(String s) =>
      (double.tryParse(s.trim().replaceAll(',', '.')) ?? 0).clamp(0, 30).toDouble();

  @override
  void dispose() {
    _taxRate.dispose();
    _service.dispose();
    super.dispose();
  }

  Widget _percentField(String label, TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: label, hintText: hint, suffixText: '%'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: '세금 · 봉사료',
      primaryLabel: '저장',
      onPrimary: () => Navigator.pop(
        context,
        widget.menu.copyWith(
          taxIncluded: _included,
          taxRatePercent: _included ? 0 : _parse(_taxRate.text),
          serviceChargePercent: _parse(_service.text),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('메뉴판에 적힌 대로 정해 주세요. 이 가게에서 다시 주문할 때도 그대로 써요.',
              style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.4)),
          const SizedBox(height: 8),
          SwitchRow(
            title: '가격에 세금이 포함돼 있어요',
            subtitle: '일본 税込, 한국·유럽 대부분',
            value: _included,
            onChanged: (v) => setState(() => _included = v),
          ),
          if (!_included) _percentField('별도 세율', _taxRate, '예) 일본 10, 태국 7'),
          _percentField('봉사료', _service, '없으면 비워 두세요'),
        ],
      ),
    );
  }
}

class _ItemEdit {
  const _ItemEdit({required this.nameKo, required this.name, required this.priceMinor})
      : deleted = false;
  const _ItemEdit.deleted()
      : nameKo = '',
        name = '',
        priceMinor = 0,
        deleted = true;

  final String nameKo;
  final String name;
  final int priceMinor;
  final bool deleted;
}

/// 잘못 읽은 메뉴 이름·가격을 고치거나, 메뉴판에 없는 메뉴를 추가한다.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item, required this.currency});

  final MenuItem? item;
  final Currency currency;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _nameKo = TextEditingController(text: widget.item?.nameKo);
  late final _name = TextEditingController(text: widget.item?.name);
  late final _price = TextEditingController(
      text: (widget.item?.priceMinor ?? 0) == 0
          ? ''
          : formatMoneyPlain(widget.item!.priceMinor, widget.currency));

  @override
  void dispose() {
    for (final c in [_nameKo, _name, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _nameKo,
      builder: (context, value, _) => SheetScaffold(
        title: isNew ? '메뉴 추가' : '메뉴 고치기',
        primaryLabel: '저장',
        onPrimary: value.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _ItemEdit(
                  nameKo: _nameKo.text.trim(),
                  name: _name.text.trim(),
                  priceMinor: parseMoneyInput(_price.text, widget.currency) ?? 0,
                )),
        secondaryLabel: isNew ? null : '삭제',
        onSecondary: () => Navigator.pop(context, const _ItemEdit.deleted()),
        child: Column(
          children: [
            TextField(
              controller: _nameKo,
              autofocus: isNew,
              decoration: const InputDecoration(labelText: '이름', hintText: '예) 라멘'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '메뉴판에 적힌 이름', hintText: '예) ラーメン'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                  labelText: '가격', hintText: '0', suffixText: widget.currency.code),
            ),
          ],
        ),
      ),
    );
  }
}
