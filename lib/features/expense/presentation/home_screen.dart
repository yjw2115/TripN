import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/receipt_review_screen.dart';
import '../../receipt/presentation/widgets/category_badge.dart';
import '../../trip/presentation/trip_sheets.dart';
import '../domain/expense.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _capture(BuildContext context, WidgetRef ref,
      {required bool fromGallery}) async {
    final service = ref.read(receiptImageServiceProvider);
    try {
      final paths = fromGallery
          ? await service.pickFromGallery()
          : await service.scan();
      if (paths != null && context.mounted) {
        context.push('/analyze', extra: paths);
      }
    } on PlatformException catch (e) {
      debugPrint('Capture failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fromGallery
            ? '사진을 불러오지 못했어요.'
            : '카메라를 열지 못했어요. 권한을 확인하거나 앨범에서 선택해 주세요.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(currentTripProvider);
    final expenses = ref.watch(expensesProvider);
    final memberCount = ref.watch(membersProvider).value?.length;
    ref.watch(rateBackfillProvider);
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: trip.hasValue ? () => showTripSwitcher(context, ref) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(trip.value?.name ?? '여행N',
                      overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.expand_more_rounded,
                    color: AppColors.textSub),
              ],
            ),
          ),
        ),
        actions: [
          if (memberCount != null)
            TextButton.icon(
              onPressed: () => context.push('/trip'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
              icon: const Icon(Icons.group_outlined, size: 20),
              label: Text('$memberCount명'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      // Riverpod이 자동 재시도하는 동안에도 상태는 로딩이라, 오류가 있으면 먼저 보여준다.
      body: expenses.hasValue
          ? _ExpenseList(expenses: expenses.requireValue)
          : expenses.hasError
              ? _ErrorView(
                  error: expenses.error!,
                  onRetry: () => ref.invalidate(currentUserProvider),
                )
              : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => _capture(context, ref, fromGallery: false),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('영수증 스캔하기'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _capture(context, ref, fromGallery: true),
                    child: const Text('앨범에서 불러오기'),
                  ),
                  const Text('·', style: TextStyle(color: AppColors.textHint)),
                  TextButton(
                    onPressed: () => context.push('/menus'),
                    child: const Text('메뉴판으로 주문'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) return const _EmptyView();
    final byDay = groupBy(expenses,
        (Expense e) => DateTime(e.paidAt.year, e.paidAt.month, e.paidAt.day));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _SummaryCard(expenses: expenses),
        for (final day in byDay.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
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

/// 지출할 때 고정한 환율로 원화 합계를 보여주고, 통화별 합계는 그 아래 작게 둔다.
/// 동행자가 있으면 정산 화면으로 가는 버튼을 둔다.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCompanions = (ref.watch(membersProvider).value?.length ?? 0) > 1;
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('지출 ${expenses.length}건',
                  style:
                      const TextStyle(fontSize: 14, color: AppColors.textSub)),
              const Spacer(),
              if (hasCompanions)
                TextButton(
                  onPressed: () => context.push('/settlement'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('정산하기 ›'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(formatMoney(krwTotal, Currency.krw),
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5)),
          if (!onlyKrw)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [for (final t in totals.entries) formatMoney(t.value, t.key)]
                    .join(' · '),
                style: const TextStyle(fontSize: 14, color: AppColors.textHint),
              ),
            ),
          if (withoutRate > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('환율을 아직 정하지 못한 지출 $withoutRate건은 빠져 있어요',
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.warning)),
            ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지출을 삭제할까요?'),
        content: Text('${expense.title} · ${formatMoney(expense.totalMinor, expense.currency)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    final trip = await ref.read(currentTripProvider.future);
    await ref.read(expenseRepositoryProvider).deleteExpense(trip.id, expense.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = expense.receipt;
    final itemCount = receipt?.items.length ?? 0;
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
      subtitle: Text(
        [
          if (settled) '정산 완료',
          DateFormat('HH:mm').format(expense.paidAt),
          if (expense.source == 'menu') '메뉴판 주문',
          if (itemCount > 0) '품목 $itemCount개',
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
      onTap: receipt == null
          ? null
          : () => context.push('/review',
              extra: ReviewArgs(
                  receipt: receipt,
                  expenseId: expense.id,
                  payerId: expense.payerId,
                  participantIds: expense.participantIds,
                  rate: expense.rate,
                  settled: settled)),
      onLongPress: () => _delete(context, ref),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_rounded,
                  size: 44, color: AppColors.primaryDeep),
            ),
            const SizedBox(height: 20),
            const Text('첫 영수증을 찍어 보세요',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              '어느 나라 영수증이든 품목과 금액을\n자동으로 정리해 드려요.\n영수증이 없으면 메뉴판으로 주문해 기록해요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.textHint),
            ),
          ],
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
            const Icon(Icons.cloud_off_rounded,
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
