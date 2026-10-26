import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/toast.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../domain/menu.dart';

/// 찍어 둔 메뉴판을 지운다 (목록에서 길게 누를 때, 메뉴판 화면의 삭제). 지웠으면 true.
/// 이 메뉴판으로 이미 기록한 지출은 그대로 남는다.
Future<bool> confirmDeleteMenu(
    BuildContext context, WidgetRef ref, Menu menu) async {
  final confirmed = await showConfirmDialog(context,
      title: '메뉴판을 지울까요?',
      body:
          '${menu.storeName.isEmpty ? '이 메뉴판' : menu.storeName}을 목록에서 지워요. 이미 기록한 지출은 그대로예요.',
      confirmLabel: '지우기',
      destructive: true);
  if (!confirmed || !context.mounted) return false;
  final tripId = ref.read(currentTripProvider).value?.id;
  if (tripId == null) return false;
  reportWriteErrors(
      context, ref.read(menuRepositoryProvider).delete(tripId, menu.id));
  showToast(context, '메뉴판을 지웠어요', kind: ToastKind.success);
  return true;
}
