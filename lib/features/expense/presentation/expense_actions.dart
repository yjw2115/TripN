import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/toast.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';

/// 지출을 지운다 (목록에서 밀거나 길게 누를 때, 지출 수정 화면의 삭제).
/// 동행자 모두에게서 사라지고 되돌릴 수 없어서 먼저 묻는다. 지웠으면 true.
Future<bool> confirmDeleteExpense(
  BuildContext context,
  WidgetRef ref, {
  required String expenseId,
  required String label,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: '지출을 삭제할까요?',
    body: '$label\n동행자 모두의 지출과 정산에서 빠지고 되돌릴 수 없어요.',
    confirmLabel: '삭제',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return false;
  final trip = await ref.read(currentTripProvider.future);
  if (!context.mounted) return false;
  // 기기에 먼저 반영돼서 기다리지 않는다 (오프라인이면 서버 응답이 늦다).
  reportWriteErrors(
      context, ref.read(expenseRepositoryProvider).deleteExpense(trip.id, expenseId));
  showToast(context, '지출을 삭제했어요', kind: ToastKind.success);
  return true;
}
