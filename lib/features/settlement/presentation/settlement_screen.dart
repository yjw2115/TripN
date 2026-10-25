import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../expense/domain/expense.dart';
import '../../receipt/presentation/widgets/category_badge.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/widgets/account_sheet.dart';
import '../../trip/presentation/widgets/bank_picker.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/settlement.dart';
import 'games/game_icon.dart';

String _won(int krw) => formatMoney(krw, Currency.krw);

/// 지금까지의 지출로 누가 누구에게 얼마 보낼지 보여준다. 여행 중간에도 볼 수 있다.
/// 외화로 쓴 여행이면 현지 화폐로 얼마인지도 함께 보여준다 (복사·메시지는 원화).
/// 미니게임으로 정한 내기가 있으면 반영하고, 언제든 원래 정산으로 되돌릴 수 있다.
/// 일부 지출만 골라 미리 정산하고 정산 완료로 표시할 수 있다. 정산 완료한 지출은 다음 정산에서 빠진다.
class SettlementScreen extends ConsumerStatefulWidget {
  const SettlementScreen({super.key});

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  /// 함께 보여줄 현지 화폐. null이면 가장 많이 쓴 외화, 'KRW'면 원화만.
  String? _localCode;

  /// 이번에 정산할 지출. null이면 아직 정산 전인 지출 모두.
  Set<String>? _only;

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
    final open = [for (final e in expenses) if (!e.isSettled) e];
    final settled = [for (final e in expenses) if (e.isSettled) e];
    // 고른 뒤 지워졌거나 다른 사람이 정산한 지출은 뺀다.
    final only = _only?.intersection({for (final e in open) e.id});
    final result =
        settle(expenses, members, bet: trip.settlementBet, only: only);
    final partial = result.leftOutCount > 0;
    final options = localCurrenciesOf(result.expenses);
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
            const SizedBox(height: 4),
            Row(
              children: [
                Text(partial ? '고른 지출' : '총 지출',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textSub)),
                const Spacer(),
                if (open.isNotEmpty)
                  TextButton(
                    onPressed: () => _pickExpenses(
                        open, {for (final e in result.expenses) e.id}),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('지출 고르기'),
                  ),
              ],
            ),
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
            Text(
                open.isEmpty && settled.isNotEmpty
                    ? '모든 지출을 정산했어요'
                    : [
                        '${members.length}명',
                        '지출 ${result.expenses.length}건',
                        if (partial) '고르지 않은 ${result.leftOutCount}건은 빠져 있어요',
                      ].join(' · '),
                style: const TextStyle(fontSize: 14, color: AppColors.textHint)),
            if (result.unratedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '환율을 아직 정하지 못한 지출 ${result.unratedCount}건은 빠져 있어요',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.warning)),
              ),
            if (settled.isNotEmpty) ...[
              const Divider(height: 24, color: AppColors.border),
              _SettledLine(
                count: settled.length,
                onTap: () => _showSettled(trip.id, settled),
              ),
            ],
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
          if (members.length > 1 &&
              (result.totalKrw > 0 || trip.settlementBet != null)) ...[
            const SizedBox(height: 12),
            _BetCard(
              settlement: result,
              onPlay: () => _playBet(context),
              onReset: () => _resetBet(context, trip),
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
              if (result.bet != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    '내기 금액은 게임에서 걸린 사람이 더 내고, 그만큼 다른 참여자가 덜 내요.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textHint, height: 1.4),
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
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textSub,
                  ),
                  onPressed: result.expenses.isEmpty
                      ? null
                      : () => _finish(trip, result),
                  child: const Text('정산 완료'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Builder(
                  builder: (context) => FilledButton.icon(
                    onPressed: result.totalKrw == 0
                        ? null
                        : () {
                            final box =
                                context.findRenderObject() as RenderBox?;
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
            ],
          ),
        ),
      ),
    );
  }

  /// 이번에 정산할 지출을 고른다. 정산 전인 지출을 모두 고르면 "모두"로 돌아간다.
  Future<void> _pickExpenses(List<Expense> open, Set<String> current) async {
    final picked = await showAppSheet<Set<String>>(
      context,
      (context) => _ExpensePickerSheet(expenses: open, initial: current),
    );
    if (picked == null) return;
    final rated = {for (final e in open) if (e.totalKrw != null) e.id};
    setState(() => _only = picked.containsAll(rated) ? null : picked);
  }

  /// 이번 정산에 넣은 지출을 정산 완료로 표시하고 홈으로 돌아간다.
  /// 반영한 내기는 이번 정산에 썼으니 지운다 (남은 정산에 또 들어가지 않게).
  Future<void> _finish(Trip trip, Settlement result) async {
    final count = result.expenses.length;
    final confirmed = await confirmDialog(
      context,
      title: '지출 $count건을 정산 완료로 할까요?',
      body: [
        '보낼 돈을 다 주고받았으면 눌러 주세요. 정산한 지출은 회색으로 바뀌고 다음 정산에서 빠져요.',
        if (result.bet != null) '게임 결과도 이번 정산에 넣고 지워요.',
      ].join(' '),
      confirmLabel: '정산 완료',
    );
    if (!confirmed || !mounted) return;
    reportWriteErrors(
        context,
        Future.wait([
          ref.read(expenseRepositoryProvider).setSettled(
              trip.id, [for (final e in result.expenses) e.id], DateTime.now()),
          if (result.bet != null)
            ref.read(tripRepositoryProvider).setSettlementBet(trip.id, null),
        ]));
    setState(() => _only = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('지출 $count건을 정산했어요')));
    Navigator.of(context).maybePop();
  }

  void _showSettled(String tripId, List<Expense> settled) {
    showAppSheet<void>(
      context,
      (context) => _SettledSheet(
        expenses: settled,
        onUndo: (batch) => _undoSettled(tripId, batch),
      ),
    );
  }

  /// 한 번에 정산한 지출을 다시 정산할 지출로 돌린다.
  Future<void> _undoSettled(String tripId, List<Expense> batch) async {
    final confirmed = await confirmDialog(
      context,
      title: '이 정산을 되돌릴까요?',
      body: '지출 ${batch.length}건이 다시 정산할 지출로 돌아가요. 동행자 모두의 정산 화면이 함께 바뀌어요.',
      confirmLabel: '되돌리기',
    );
    if (!confirmed || !mounted) return;
    reportWriteErrors(
        context,
        ref.read(expenseRepositoryProvider)
            .setSettled(tripId, [for (final e in batch) e.id], null));
  }

  Future<void> _playBet(BuildContext context) async {
    final applied = await context.push<bool>('/settlement/bet');
    if (applied == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게임 결과를 정산에 반영했어요')));
    }
  }

  /// 동행자 모두의 정산이 원래대로 돌아가서 한 번 묻는다.
  Future<void> _resetBet(BuildContext context, Trip trip) async {
    final confirmed = await confirmDialog(
      context,
      title: '원래 정산으로 되돌릴까요?',
      body: '게임 결과를 지우고 지출대로 다시 나눠요. 동행자 모두의 정산 화면이 함께 바뀌어요.',
      confirmLabel: '되돌리기',
    );
    if (!confirmed || !context.mounted) return;
    reportWriteErrors(
        context, ref.read(tripRepositoryProvider).setSettlementBet(trip.id, null));
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
                leading: BankIcon(account.bank, size: 28),
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

/// 미니게임으로 정하기. 내기를 반영했으면 결과와 되돌리기를 보여준다.
class _BetCard extends StatelessWidget {
  const _BetCard(
      {required this.settlement, required this.onPlay, required this.onReset});

  final Settlement settlement;
  final VoidCallback onPlay;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final applied = settlement.bet;
    final skip = settlement.betSkip;
    if (applied == null && skip == null) {
      return Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: AppColors.primaryLight, shape: BoxShape.circle),
                  child: const Text('🎲', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('미니게임으로 정하기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('잔돈 몰아주기나 한 턱 쏘기를 게임으로 정해요',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textHint)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint),
              ],
            ),
          ),
        ),
      );
    }

    final game = applied?.bet.game;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: applied != null ? const Color(0xFFFFF6E0) : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: applied != null
                ? const Color(0xFFFFE2A8)
                : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.surface, shape: BoxShape.circle),
                child: game == null
                    ? const Text('🎲', style: TextStyle(fontSize: 24))
                    : GameIcon(game, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (applied != null) ...[
                      Text(
                          '${game!.label}${particle(game.label, '으로', '로')} 정했어요',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSub)),
                      const SizedBox(height: 2),
                      Text(betSummary(applied),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('${_won(applied.amount)} 더 내요',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger)),
                    ] else
                      Text(
                        switch (skip!) {
                          BetSkip.loserGone =>
                            '게임에서 걸린 사람이 여행에서 빠져서 원래 정산으로 보여요',
                          BetSkip.expenseGone =>
                            '내기에 건 지출이 지워져서 원래 정산으로 보여요',
                          BetSkip.expenseUnrated =>
                            '내기에 건 지출의 환율을 아직 못 정해서 원래 정산으로 보여요',
                          BetSkip.expenseLeftOut =>
                            '내기에 건 지출이 이번 정산에 없어서 원래 정산으로 보여요',
                        },
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.warning),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onReset,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(applied != null ? '원래 정산으로' : '내기 지우기'),
              ),
              TextButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('다시 하기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 미리 정산한 지출이 있다고 알리고, 눌러서 보거나 되돌린다.
class _SettledLine extends StatelessWidget {
  const _SettledLine({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 18, color: AppColors.textHint),
            const SizedBox(width: 6),
            Expanded(
              child: Text('미리 정산한 지출 $count건은 빠져 있어요',
                  style:
                      const TextStyle(fontSize: 14, color: AppColors.textSub)),
            ),
            const Text('보기',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDeep)),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.primaryDeep),
          ],
        ),
      ),
    );
  }
}

/// 이번에 정산할 지출을 고른다. 환율을 못 정한 지출은 고를 수 없고, 한 건 이상 골라야 한다.
class _ExpensePickerSheet extends StatefulWidget {
  const _ExpensePickerSheet({required this.expenses, required this.initial});

  /// 아직 정산 전인 지출.
  final List<Expense> expenses;
  final Set<String> initial;

  @override
  State<_ExpensePickerSheet> createState() => _ExpensePickerSheetState();
}

class _ExpensePickerSheetState extends State<_ExpensePickerSheet> {
  late final Set<String> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final rated = [
      for (final e in widget.expenses)
        if (e.totalKrw != null) e,
    ];
    final all = rated.every((e) => _picked.contains(e.id));
    final total = rated
        .where((e) => _picked.contains(e.id))
        .fold(0, (sum, e) => sum + e.totalKrw!);
    return SheetScaffold(
      title: '어떤 지출을 정산할까요?',
      primaryLabel: _picked.isEmpty
          ? '한 건 이상 골라 주세요'
          : '${_picked.length}건 · ${_won(total)} 정산하기',
      onPrimary: _picked.isEmpty
          ? null
          : () => Navigator.pop(context, {..._picked}),
      child: Column(
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('모두',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            value: all,
            onChanged: (_) => setState(() => all
                ? _picked.clear()
                : _picked.addAll(rated.map((e) => e.id))),
          ),
          for (final e in widget.expenses)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              secondary: CategoryBadge(e.category, size: 36),
              title: Text(e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15)),
              subtitle: Text(
                  [
                    DateFormat('M월 d일', 'ko').format(e.paidAt),
                    e.totalKrw == null ? '환율을 정하면 고를 수 있어요' : _won(e.totalKrw!),
                  ].join(' · '),
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.textHint)),
              value: _picked.contains(e.id),
              onChanged: e.totalKrw == null
                  ? null
                  : (on) => setState(() =>
                      on == true ? _picked.add(e.id) : _picked.remove(e.id)),
            ),
        ],
      ),
    );
  }
}

/// 미리 정산한 지출을 정산한 때별로 묶어 보여주고, 묶음째 되돌릴 수 있다.
class _SettledSheet extends StatelessWidget {
  const _SettledSheet({required this.expenses, required this.onUndo});

  final List<Expense> expenses;
  final ValueChanged<List<Expense>> onUndo;

  @override
  Widget build(BuildContext context) {
    final batches = groupBy(expenses, (Expense e) => e.settledAt!)
        .entries
        .sorted((a, b) => b.key.compareTo(a.key));
    return SheetScaffold(
      title: '미리 정산한 지출',
      primaryLabel: '닫기',
      onPrimary: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final batch in batches) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${DateFormat('M월 d일 HH:mm', 'ko').format(batch.key)} 정산',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                          '${batch.value.length}건 · '
                          '${_won(batch.value.fold(0, (sum, e) => sum + (e.totalKrw ?? 0)))}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textHint)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onUndo(batch.value);
                  },
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('되돌리기'),
                ),
              ],
            ),
            for (final e in batch.value)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CategoryBadge(e.category, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, color: AppColors.textSub)),
                    ),
                    Text(
                        e.totalKrw == null
                            ? formatMoney(e.totalMinor, e.currency)
                            : _won(e.totalKrw!),
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textSub)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// 현지 화폐로도 볼 통화를 드롭다운으로 고른다. 외화를 여러 개 썼을 때 바꿀 수 있다.
class _LocalCurrencyPicker extends StatelessWidget {
  const _LocalCurrencyPicker(
      {required this.options, required this.selected, required this.onSelected});

  final List<LocalCurrency> options;
  final LocalCurrency? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    DropdownMenuItem<String> item(Currency c, String label) =>
        DropdownMenuItem(
          value: c.code,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.flag.isNotEmpty) ...[
                Text(c.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.only(left: 20, right: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Text('함께 볼 화폐',
              style: TextStyle(fontSize: 14, color: AppColors.textSub)),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected?.currency.code ?? Currency.krw.code,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.expand_more_rounded,
                  color: AppColors.textSub),
              items: [
                for (final o in options)
                  item(o.currency, '${o.currency.nameKo} ${o.currency.code}'),
                item(Currency.krw, '원화만'),
              ],
              onChanged: (code) {
                if (code != null) onSelected(code);
              },
            ),
          ),
        ],
      ),
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
      subtitle: Text(
          [
            '낸 돈 ${_won(balance.paid)}',
            '쓴 돈 ${_won(balance.owed)}',
            if (balance.bet != 0)
              '내기 ${balance.bet > 0 ? '+' : '−'}${_won(balance.bet.abs())}',
          ].join(' · '),
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
