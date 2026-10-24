import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/presentation/widgets/account_sheet.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/settlement.dart';

String _won(int krw) => formatMoney(krw, Currency.krw);

/// 지금까지의 지출로 누가 누구에게 얼마 보낼지 보여준다. 여행 중간에도 볼 수 있다.
/// 외화로 쓴 여행이면 현지 화폐로 얼마인지도 함께 보여준다 (복사·메시지는 원화).
class SettlementScreen extends ConsumerStatefulWidget {
  const SettlementScreen({super.key});

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  /// 함께 보여줄 현지 화폐. null이면 가장 많이 쓴 외화, 'KRW'면 원화만.
  String? _localCode;

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(currentTripProvider).value;
    final members = ref.watch(membersProvider).value;
    final expenses = ref.watch(expensesProvider).value;
    if (trip == null || members == null || expenses == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('정산')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final result = settle(expenses, members);
    final options = localCurrenciesOf(expenses);
    final local = _localCode == Currency.krw.code
        ? null
        : options.firstWhereOrNull((o) => o.currency.code == _localCode) ??
            options.firstOrNull;
    String? inLocal(int krw) => local == null
        ? null
        : '≈ ${formatMoney(local.fromKrw(krw), local.currency)}';
    return Scaffold(
      appBar: AppBar(title: const Text('정산')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SectionCard(children: [
            const SizedBox(height: 8),
            const Text('총 지출',
                style: TextStyle(fontSize: 14, color: AppColors.textSub)),
            const SizedBox(height: 4),
            Text(_won(result.totalKrw),
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5)),
            if (inLocal(result.totalKrw) case final text?)
              Text(text,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub)),
            Text('${members.length}명 · 지출 ${expenses.length - result.unratedCount}건',
                style: const TextStyle(fontSize: 14, color: AppColors.textHint)),
            if (result.unratedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '환율을 아직 정하지 못한 지출 ${result.unratedCount}건은 빠져 있어요',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.warning)),
              ),
            const SizedBox(height: 8),
          ]),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 12),
            _LocalCurrencyPicker(
              options: options,
              selected: local,
              onSelected: (code) => setState(() => _localCode = code),
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: '보낼 돈',
            children: [
              if (result.transfers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('서로 보낼 돈이 없어요',
                        style: TextStyle(color: AppColors.textHint)),
                  ),
                ),
              for (final t in result.transfers)
                _TransferRow(
                  transfer: t,
                  local: inLocal(t.amount),
                  onTap: () =>
                      _showTransfer(context, trip.id, t, inLocal(t.amount)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '각자 낸 돈과 쓴 돈',
            children: [
              for (final b in result.balances)
                _BalanceRow(balance: b, local: inLocal(b.net.abs())),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '품목마다 같이 먹은 사람을 고르면 그 사람들끼리만 나눠요. '
                  '세금·봉사료·할인은 각자 몫에 비례해 나누고, 남는 1원은 결제한 사람이 더 낸 것으로 쳐요.',
                  style: TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.4),
                ),
              ),
              if (local != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    '${local.currency.nameKo} 금액은 이 여행의 ${local.currency.nameKo} 지출 평균 환율'
                    '(${formatRate(FixedRate(krwPerUnit: local.krwPerUnit, source: RateSource.koreaexim), local.currency)})로 '
                    '바꾼 참고 금액이에요. 복사와 정산 요청 메시지는 원화로 해요.',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textHint, height: 1.4),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Builder(
            builder: (context) => FilledButton.icon(
              onPressed: result.totalKrw == 0
                  ? null
                  : () {
                      final box = context.findRenderObject() as RenderBox?;
                      SharePlus.instance.share(ShareParams(
                        text: settlementMessage(trip.name, result),
                        sharePositionOrigin: box == null
                            ? null
                            : box.localToGlobal(Offset.zero) & box.size,
                      ));
                    },
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              label: const Text('정산 요청 보내기'),
            ),
          ),
        ),
      ),
    );
  }

  /// 금액이나 계좌·금액을 복사해서 송금 앱에 붙여 넣는다 (원화). 계좌가 없으면 등록하게 한다.
  Future<void> _showTransfer(
      BuildContext context, String tripId, Transfer t, String? local) async {
    final account = t.to.account;
    void copy(BuildContext sheetContext, String text, String done) {
      Clipboard.setData(ClipboardData(text: text));
      Navigator.pop(sheetContext);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t.from.name} → ${t.to.name} ${_won(t.amount)}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  if (local != null)
                    Text(local,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textSub)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('금액 복사'),
              subtitle: Text('${t.amount}'),
              onTap: () => copy(sheetContext, '${t.amount}', '금액을 복사했어요'),
            ),
            if (account != null)
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('계좌와 금액 복사'),
                subtitle: Text('${account.display} ${_won(t.amount)}'),
                onTap: () => copy(sheetContext,
                    '${account.display} ${_won(t.amount)}', '계좌와 금액을 복사했어요'),
              )
            else
              ListTile(
                leading: const Icon(Icons.add_card_outlined),
                title: Text('${t.to.name}님 계좌 등록'),
                subtitle: const Text('등록하면 보낼 사람이 바로 복사할 수 있어요'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  editAccount(context, ref, tripId, t.to);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 현지 화폐로도 볼 통화를 고른다. 외화를 여러 개 썼을 때 바꿀 수 있다.
class _LocalCurrencyPicker extends StatelessWidget {
  const _LocalCurrencyPicker(
      {required this.options, required this.selected, required this.onSelected});

  final List<LocalCurrency> options;
  final LocalCurrency? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('함께 볼 화폐',
            style: TextStyle(fontSize: 14, color: AppColors.textSub)),
        for (final o in options)
          ChoiceChip(
            label: Text('${o.currency.nameKo} ${o.currency.code}'),
            selected: selected?.currency == o.currency,
            onSelected: (_) => onSelected(o.currency.code),
          ),
        ChoiceChip(
          label: const Text('원화만'),
          selected: selected == null,
          onSelected: (_) => onSelected(Currency.krw.code),
        ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow(
      {required this.transfer, required this.local, required this.onTap});

  final Transfer transfer;

  /// "≈ ¥5,330"처럼 현지 화폐로 본 금액. 원화만 볼 때는 null.
  final String? local;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            MemberAvatar(transfer.from, size: 36),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 18, color: AppColors.textHint),
            ),
            MemberAvatar(transfer.to, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${transfer.from.name} → ${transfer.to.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_won(transfer.amount),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (local != null)
                  Text(local!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textHint)),
              ],
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balance, required this.local});

  final MemberBalance balance;

  /// 받을 돈·보낼 돈을 현지 화폐로 본 금액.
  final String? local;

  @override
  Widget build(BuildContext context) {
    final net = balance.net;
    final (label, color) = net > 0
        ? ('${_won(net)} 받을 돈', AppColors.primaryDeep)
        : net < 0
            ? ('${_won(-net)} 보낼 돈', AppColors.danger)
            : ('정산 끝', AppColors.textHint);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: MemberAvatar(balance.member),
      title: Text(balance.member.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text('낸 돈 ${_won(balance.paid)} · 쓴 돈 ${_won(balance.owed)}',
          style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          if (local != null && net != 0)
            Text(local!,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textHint)),
        ],
      ),
    );
  }
}
