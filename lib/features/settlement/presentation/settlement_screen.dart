import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/presentation/widgets/account_sheet.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/settlement.dart';

String _won(int krw) => formatMoney(krw, Currency.krw);

/// 지금까지의 지출로 누가 누구에게 얼마 보낼지 보여준다. 여행 중간에도 볼 수 있다.
class SettlementScreen extends ConsumerWidget {
  const SettlementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  onTap: () => _showTransfer(context, ref, trip.id, t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '각자 낸 돈과 쓴 돈',
            children: [
              for (final b in result.balances) _BalanceRow(balance: b),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '품목마다 같이 먹은 사람을 고르면 그 사람들끼리만 나눠요. '
                  '세금·봉사료·할인은 각자 몫에 비례해 나누고, 남는 1원은 결제한 사람이 더 낸 것으로 쳐요.',
                  style: TextStyle(fontSize: 13, color: AppColors.textHint, height: 1.4),
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

  /// 금액이나 계좌·금액을 복사해서 송금 앱에 붙여 넣는다. 계좌가 없으면 등록하게 한다.
  Future<void> _showTransfer(
      BuildContext context, WidgetRef ref, String tripId, Transfer t) async {
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
              child: Text('${t.from.name} → ${t.to.name} ${_won(t.amount)}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
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

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.transfer, required this.onTap});

  final Transfer transfer;
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
            Text(_won(transfer.amount),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balance});

  final MemberBalance balance;

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
      trailing: Text(label,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
