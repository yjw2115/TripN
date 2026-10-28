import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/capture.dart';
import '../../receipt/presentation/widgets/category_badge.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/members_sheet.dart';
import '../domain/expense.dart';
import '../../../core/theme/app_icons.dart';
import 'expense_actions.dart';
import '../../../core/ui/controls.dart';
import '../../../core/ui/pressable.dart';

/// 지출 탭. 앱바 없이 맨 위부터 요약 카드와 지출 목록을 보여준다.
/// 여행 이름·인원·스캔 버튼은 아래 플로팅 바(app_shell.dart)에 있다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    ref.watch(rateBackfillProvider);
    return Scaffold(
      // 플로팅 바 뒤로 목록이 지나가도록 아래는 비워 두지 않는다.
      body: SafeArea(
        bottom: false,
        // Riverpod이 자동 재시도하는 동안에도 상태는 로딩이라, 오류가 있으면 먼저 보여준다.
        child: expenses.hasValue
            ? _ExpenseList(expenses: expenses.requireValue)
            : expenses.hasError
                ? _ErrorView(
                    error: expenses.error!,
                    onRetry: () => ref.invalidate(currentUserProvider),
                  )
                : const Center(child: AppSpinner()),
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    // 플로팅 바 높이만큼 아래를 띄운다 (AppShell이 extendBody라 MediaQuery에 들어 있다).
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    if (expenses.isEmpty) return _EmptyView(bottomPadding: bottom);
    final byDay = groupBy(expenses,
        (Expense e) => DateTime(e.paidAt.year, e.paidAt.month, e.paidAt.day));
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
      children: [
        _SummaryCard(expenses: expenses),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 28, 4, 0),
          child: Text('지출 내역',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        for (final (i, day) in byDay.entries.indexed) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(4, i == 0 ? 12 : 24, 4, 8),
            child: Text(DateFormat('M월 d일 EEEE', 'ko').format(day.key),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [for (final e in day.value) _ExpenseTile(expense: e)],
            ),
          ),
        ],
      ],
    );
  }
}

/// 맨 위 요약 칸. 지출 목록과 구분되도록 연한 초록 바탕 한 덩어리에 원화 합계, 정산 입구,
/// 지출을 남기는 다른 길(직접 입력·앨범·메뉴판)을 묶는다.
/// 합계는 지출할 때 고정한 환율로 더하고, 통화별 합계는 그 아래 작게 둔다.
/// 합계 오른쪽은 동행자가 있으면 정산하기, 혼자면 동행자 추가.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.expenses});

  final List<Expense> expenses;

  /// 회색 바탕에서 또렷이 보이도록 primaryLight보다 조금 진한 초록 (primary 35% + 흰색).
  static const _tint = Color(0xFFE6F5E0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value;
    final totals = <Currency, int>{};
    var krwTotal = 0;
    var withoutRate = 0;
    for (final e in expenses) {
      totals[e.currency] = (totals[e.currency] ?? 0) + e.totalMinor;
      final krw = e.totalKrw;
      if (krw == null) {
        withoutRate++;
      } else {
        krwTotal += krw;
      }
    }
    final onlyKrw = totals.keys.every((c) => c == Currency.krw);
    final days = expenses.map((e) => e.paidAt).sorted((a, b) => a.compareTo(b));
    final format = DateFormat('M.d');
    final first = format.format(days.first);
    final last = format.format(days.last);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('지출 ${expenses.length}건',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textSub)),
                    const Spacer(),
                    Text(first == last ? first : '$first – $last',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textHint)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(formatMoney(krwTotal, Currency.krw),
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5)),
                    ),
                    if (members != null)
                      members.length > 1
                          ? _SettleButton(
                              label: '정산하기',
                              onTap: () => context.push('/settlement'),
                            )
                          : _SettleButton(
                              label: '동행자 추가',
                              onTap: () => showMembersSheet(context),
                            ),
                  ],
                ),
                if (!onlyKrw)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        for (final t in totals.entries)
                          formatMoney(t.value, t.key)
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textHint),
                    ),
                  ),
                if (withoutRate > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '환율을 아직 정하지 못한 지출 $withoutRate건은 빠져 있어요',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.warning)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _QuickActions(),
        ],
      ),
    );
  }
}

/// 합계 오른쪽의 글자 버튼.
class _SettleButton extends StatelessWidget {
  const _SettleButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        // 글자보다 누르는 자리를 넓게 잡는다.
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDeep)),
            const SizedBox(width: 2),
            const Icon(AppIcons.chevronRight,
                size: 14, color: AppColors.primaryDeep),
          ],
        ),
      ),
    );
  }
}

/// 스캔 말고 지출을 남기는 다른 길: 직접 입력, 앨범, 메뉴판.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _QuickAction(
          icon: AppIcons.note,
          label: '직접 입력하기',
          onTap: () => enterExpenseManually(context, ref),
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: AppIcons.album,
          label: '앨범에서 불러오기',
          onTap: () => captureReceipt(context, ref, fromGallery: true),
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: AppIcons.menu,
          label: '메뉴판 주문',
          onTap: () => context.push('/menus'),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
            child: Column(
              children: [
                Icon(icon, size: 24, color: AppColors.primaryDeep),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  Future<bool> _delete(BuildContext context, WidgetRef ref) =>
      confirmDeleteExpense(context, ref,
          expenseId: expense.id,
          label:
              '${expense.title} · ${formatMoney(expense.totalMinor, expense.currency)}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value ?? const [];
    final payer = members.length > 1
        ? members.firstWhereOrNull((m) => m.id == expense.payerId)
        : null;
    // 미리 정산한 지출은 회색으로 두고 금액에 줄을 긋는다.
    final settled = expense.isSettled;
    final amountStyle = settled
        ? const TextStyle(
            color: AppColors.textHint,
            decoration: TextDecoration.lineThrough,
            decorationColor: AppColors.textHint)
        : const TextStyle();
    // 왼쪽으로 밀면 지운다 (길게 눌러도 된다). 지울지는 대화상자에서 한 번 더 묻는다.
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _delete(context, ref),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.danger,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.trash, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text('삭제',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      child: _tile(context, ref, payer, settled, amountStyle),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, Member? payer, bool settled,
      TextStyle amountStyle) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Opacity(
        opacity: settled ? 0.4 : 1,
        child: CategoryBadge(expense.category, size: 40),
      ),
      title: Text(expense.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: settled ? AppColors.textHint : null)),
      // 날짜는 위 머리글에 있으니 시각과 결제한 사람만 적는다.
      subtitle: Text(
        [
          if (settled) '정산 완료',
          DateFormat('HH:mm').format(expense.paidAt),
          if (payer != null) '${payer.name} 결제',
        ].join(' · '),
        style: const TextStyle(fontSize: 13, color: AppColors.textHint),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMoney(expense.totalMinor, expense.currency),
              style: amountStyle.copyWith(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          if (expense.currency != Currency.krw)
            Text(
              expense.totalKrw == null
                  ? '환율 미정'
                  : formatMoney(expense.totalKrw!, Currency.krw),
              style: amountStyle.copyWith(
                  fontSize: 13,
                  color: expense.totalKrw == null
                      ? AppColors.warning
                      : AppColors.textHint),
            ),
        ],
      ),
      onTap: expenseOpener(context, expense),
      onLongPress: () => _delete(context, ref),
    );
  }
}

/// 아직 지출이 없을 때. 오른쪽 아래 스캔 버튼을 가리키고, 다른 기록 방법을 아래에 둔다.
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 8 - bottomPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                    color: AppColors.primaryLight, shape: BoxShape.circle),
                child: const Icon(AppIcons.receiptFill,
                    size: 44, color: AppColors.primaryDeep),
              ),
              const SizedBox(height: 20),
              const Text('첫 영수증을 찍어 보세요',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                '오른쪽 아래 초록 버튼을 누르면 바로 찍을 수 있어요.\n어느 나라 영수증이든 품목과 금액을\n자동으로 정리해 드려요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppColors.textHint),
              ),
              const SizedBox(height: 28),
              const _QuickActions(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  /// 1단계 설정 중 흔히 만나는 Firebase 오류는 원인을 알려준다.
  String get _message {
    final e = error;
    if (e is FirebaseAuthException &&
        (e.code == 'operation-not-allowed' ||
            e.code == 'admin-restricted-operation')) {
      return 'Firebase 콘솔에서 익명 로그인을 켜 주세요.';
    }
    if (e is FirebaseException && e.plugin == 'cloud_firestore') {
      return e.code == 'permission-denied'
          ? 'Firestore 보안 규칙이 배포되지 않았어요.'
          : 'Firestore 데이터베이스에 연결하지 못했어요. (${e.code})';
    }
    return '데이터를 불러오지 못했어요.';
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('Home load error: $error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.offline,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(_message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: AppColors.textSub)),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
