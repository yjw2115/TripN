import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../domain/trip.dart';
import 'widgets/trip_widgets.dart';
import '../../../core/theme/app_icons.dart';

enum _SwitcherAction { settings, create, join }

/// 플로팅 바의 여행 이름을 누르면 여는 여행 목록. 다른 여행을 고르거나 새로 만들거나 초대 코드로 들어간다.
/// 지금 여행의 "설정"은 여행 설정 화면(이름·환율·삭제)으로 간다.
Future<void> showTripSwitcher(BuildContext context, WidgetRef ref) async {
  final action = await showAppSheet<_SwitcherAction>(
      context, (context) => const _TripSwitcher());
  if (!context.mounted) return;
  switch (action) {
    case _SwitcherAction.settings:
      context.push('/trip');
    case _SwitcherAction.create:
      await _createTrip(context, ref);
    case _SwitcherAction.join:
      context.push('/join');
    case null:
      break;
  }
}

/// 내 이름은 MY 탭에서 정한 이름, 없으면 지금 여행에서 쓰는 이름으로 채워 둔다.
/// MY 탭에 받을 계좌가 있으면 새 여행에도 넣는다.
Future<void> _createTrip(BuildContext context, WidgetRef ref) async {
  final profile = ref.read(profileProvider).value;
  final myMember = ref.read(myMemberProvider).value;
  final result = await showAppSheet<({String name, String myName})>(
    context,
    (context) => _CreateTripSheet(
      initialMyName: profile?.name ??
          (myMember == null || myMember.name == defaultMyName
              ? ''
              : myMember.name),
    ),
  );
  if (result == null || !context.mounted) return;
  final user = await ref.read(currentUserProvider.future);
  if (!context.mounted) return;
  reportWriteErrors(
    context,
    ref.read(tripRepositoryProvider).createTrip(
        uid: user.uid,
        name: result.name,
        myName: result.myName,
        myAccount: profile?.account),
  );
}

class _TripSwitcher extends ConsumerWidget {
  const _TripSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(myTripsProvider).value ?? const [];
    final current = ref.watch(currentTripProvider).value;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text('여행',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final trip in trips)
                  ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    tileColor:
                        trip.id == current?.id ? AppColors.primaryLight : null,
                    leading: Icon(AppIcons.trip,
                        color: trip.id == current?.id
                            ? AppColors.primaryDeep
                            : AppColors.textSub),
                    title: Text(trip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    subtitle: trip.id == current?.id
                        ? const Text('지금 여행',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.primaryDeep))
                        : null,
                    trailing: trip.id == current?.id
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(
                                    context, _SwitcherAction.settings),
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.surface,
                                  minimumSize: const Size(0, 34),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  textStyle: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                                child: const Text('설정'),
                              ),
                              const SizedBox(width: 8),
                              const Icon(AppIcons.check,
                                  color: AppColors.primaryDeep),
                            ],
                          )
                        : null,
                    onTap: () {
                      final uid = ref.read(currentUserProvider).value?.uid;
                      if (uid != null && trip.id != current?.id) {
                        reportWriteErrors(context,
                            ref.read(tripRepositoryProvider).selectTrip(uid, trip.id));
                      }
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 24, indent: 24, endIndent: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(AppIcons.plus,
                      color: AppColors.primaryDeep),
                  title: const Text('새 여행 만들기'),
                  onTap: () => Navigator.pop(context, _SwitcherAction.create),
                ),
                ListTile(
                  leading: const Icon(AppIcons.key,
                      color: AppColors.primaryDeep),
                  title: const Text('초대 코드로 참여하기'),
                  onTap: () => Navigator.pop(context, _SwitcherAction.join),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateTripSheet extends StatefulWidget {
  const _CreateTripSheet({required this.initialMyName});

  final String initialMyName;

  @override
  State<_CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends State<_CreateTripSheet> {
  final _name = TextEditingController();
  late final _myName = TextEditingController(text: widget.initialMyName);

  @override
  void dispose() {
    _name.dispose();
    _myName.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final myName = _myName.text.trim();
    Navigator.pop(
        context, (name: name, myName: myName.isEmpty ? defaultMyName : myName));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _name,
      builder: (context, value, _) => SheetScaffold(
        title: '새 여행',
        primaryLabel: '만들기',
        onPrimary: value.text.trim().isEmpty ? null : _submit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('여행 이름',
                style: TextStyle(fontSize: 13, color: AppColors.textHint)),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: nameMaxLength,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  hintText: '예) 도쿄 3박 4일', counterText: ''),
            ),
            const SizedBox(height: 16),
            const Text('동행자에게 보일 내 이름',
                style: TextStyle(fontSize: 13, color: AppColors.textHint)),
            const SizedBox(height: 6),
            TextField(
              controller: _myName,
              maxLength: nameMaxLength,
              decoration:
                  const InputDecoration(hintText: '예) 지민', counterText: ''),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    );
  }
}
