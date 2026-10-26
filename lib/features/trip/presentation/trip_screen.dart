import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../domain/trip.dart';
import 'widgets/manual_rate_sheet.dart';
import 'widgets/trip_widgets.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/toast.dart';
import '../../../core/ui/controls.dart';

/// 지금 여행의 이름, 여행에서 정한 환율을 고치고 여행을 지우거나 나간다.
/// 여행 시트에서 지금 여행의 "설정"을 눌러 연다. 동행자와 초대는 동행자 시트(members_sheet.dart)에 있다.
class TripScreen extends ConsumerWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(currentTripProvider).value;
    final user = ref.watch(currentUserProvider).value;
    if (trip == null || user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: AppSpinner()),
      );
    }
    final isOwner = trip.ownerId == user.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('여행 설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SectionCard(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('여행 이름',
                  style: TextStyle(fontSize: 13, color: AppColors.textHint)),
              subtitle: Text(trip.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
              trailing: const Icon(AppIcons.edit,
                  size: 20, color: AppColors.textHint),
              onTap: () => _renameTrip(context, ref, trip),
            ),
          ]),
          if (trip.manualRates.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: '여행에서 정한 환율',
              children: [
                for (final entry in trip.manualRates.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        formatRate(
                            FixedRate(
                                krwPerUnit: entry.value,
                                source: RateSource.manual),
                            Currency.of(entry.key)),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    trailing: const Icon(AppIcons.edit,
                        size: 20, color: AppColors.textHint),
                    onTap: () =>
                        editManualRate(context, ref, Currency.of(entry.key)),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    '바꾸면 이후에 저장하는 지출부터 적용돼요. 이미 저장한 지출의 환율은 그대로예요.',
                    style: TextStyle(fontSize: 13, color: AppColors.textHint),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () => _deleteOrLeave(context, ref, trip, isOwner),
              child: Text(isOwner ? '여행 삭제' : '여행 나가기'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameTrip(BuildContext context, WidgetRef ref, Trip trip) async {
    final name = await showTextSheet(context,
        title: '여행 이름',
        initial: trip.name,
        hint: '예) 도쿄 3박 4일',
        maxLength: nameMaxLength);
    if (name == null || name.isEmpty || name == trip.name || !context.mounted) {
      return;
    }
    reportWriteErrors(
        context, ref.read(tripRepositoryProvider).renameTrip(trip, name));
  }

  /// 보던 여행을 먼저 다른 여행으로 바꾸고 홈으로 돌아간 뒤 지우거나 나간다.
  /// 마지막 여행이면 빈 "내 여행"을 하나 만들어 둔다.
  Future<void> _deleteOrLeave(
      BuildContext context, WidgetRef ref, Trip trip, bool isOwner) async {
    final confirmed = await confirmDialog(
      context,
      title: isOwner ? '여행을 삭제할까요?' : '여행에서 나갈까요?',
      body: isOwner
          ? '동행자와 지출 기록이 모두 지워지고 되돌릴 수 없어요. 함께하는 동행자의 앱에서도 사라져요.'
          : '기록한 지출은 그대로 남고, 나는 이름만 있는 동행자로 바뀌어요. 초대 코드로 다시 들어올 수 있어요.',
      confirmLabel: isOwner ? '삭제' : '나가기',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final repo = ref.read(tripRepositoryProvider);
    final user = await ref.read(currentUserProvider.future);
    final myMember = await ref.read(myMemberProvider.future);
    final others = (ref.read(myTripsProvider).value ?? const <Trip>[])
        .where((t) => t.id != trip.id)
        .toList();
    try {
      if (others.isEmpty) {
        final myName = myMember?.name ?? defaultMyName;
        await repo.createTrip(uid: user.uid, name: '내 여행', myName: myName);
      } else {
        await repo.selectTrip(user.uid, others.first.id);
      }
      if (context.mounted) context.go('/');
      if (isOwner) {
        await repo.deleteTrip(trip);
      } else {
        await repo.leaveTrip(
            tripId: trip.id, memberId: myMember!.id, uid: user.uid);
      }
      showToastOn(
          overlay,
          isOwner
              ? "'${trip.name}' 여행을 삭제했어요"
              : "'${trip.name}' 여행에서 나왔어요",
          kind: ToastKind.success);
    } catch (e) {
      debugPrint('Delete or leave failed: $e');
      showToastOn(overlay, '처리하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.',
          kind: ToastKind.error);
    }
  }
}
