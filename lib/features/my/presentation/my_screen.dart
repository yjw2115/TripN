import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/widgets/account_sheet.dart';
import '../../trip/presentation/widgets/bank_picker.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../../../core/theme/app_icons.dart';

/// 앱 버전과 빌드 번호. pubspec의 version 그대로 `1.0.0+11` 꼴.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version}+${info.buildNumber}';
});

/// MY 탭. 새 여행에 쓸 내 이름과 받을 계좌, 알림 설정, 앱 버전.
/// 이름과 계좌는 여행마다 멤버에 따로 저장되니, 여기 값은 새 여행을 만들거나 참여할 때 채워 넣는 기본값이다.
class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  String _notifySummary(Profile profile) {
    final on = [
      if (profile.notifyExpense) '동행자 지출',
      if (profile.notifySettlement) '정산',
    ];
    return on.isEmpty ? '모두 꺼짐' : on.join(' · ');
  }

  /// MY에서 아직 정하지 않았으면 지금 여행에서 쓰는 이름.
  String? _name(Profile profile, Member? me) =>
      profile.name ?? (me == null || me.name == defaultMyName ? null : me.name);

  Future<void> _editName(
      BuildContext context, WidgetRef ref, String? current) async {
    final name = await showTextSheet(context,
        title: '내 이름',
        initial: current ?? '',
        hint: '예) 지민',
        maxLength: nameMaxLength);
    if (name == null || name.isEmpty || !context.mounted) return;
    final user = await ref.read(currentUserProvider.future);
    final trip = ref.read(currentTripProvider).value;
    final me = ref.read(myMemberProvider).value;
    final repo = ref.read(tripRepositoryProvider);
    if (!context.mounted) return;
    reportWriteErrors(
        context,
        Future.wait([
          repo.setProfileName(user.uid, name),
          // 지금 여행에서 아직 이름을 정하지 않았으면('나') 같이 바꾼다.
          if (trip != null && me != null && me.name == defaultMyName)
            repo.renameMember(trip.id, me.id, name),
        ]));
  }

  Future<void> _editAccount(BuildContext context, WidgetRef ref,
      Profile profile, String? name) async {
    final result = await showAccountSheet(context,
        title: '내 계좌',
        initial: profile.account,
        holder: name ?? '',
        note: '새 여행을 만들거나 참여하면 이 계좌가 자동으로 들어가요. 여행의 동행자에게만 보여요.');
    if (result == null || !context.mounted) return;
    final account = result.account;
    final user = await ref.read(currentUserProvider.future);
    final trip = ref.read(currentTripProvider).value;
    final me = ref.read(myMemberProvider).value;
    final repo = ref.read(tripRepositoryProvider);
    if (!context.mounted) return;
    reportWriteErrors(
        context,
        Future.wait([
          repo.setProfileAccount(user.uid, account),
          // 지금 여행에 내 계좌가 아직 없으면 같이 넣는다.
          if (account != null && trip != null && me != null && me.account == null)
            repo.setAccount(trip.id, me.id, account),
        ]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value ?? const Profile();
    final me = ref.watch(myMemberProvider).value;
    final name = _name(profile, me);
    final account = profile.account;
    final version = ref.watch(appVersionProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(children: [
                _ProfileCard(
                    name: name, onTap: () => _editName(context, ref, name)),
                const SizedBox(height: 12),
                SectionCard(children: [
                  _Row(
                    leading: account == null
                        ? const Icon(AppIcons.bank,
                            color: AppColors.textSub)
                        : BankIcon(account.bank, size: 28),
                    title: '받을 계좌',
                    subtitle: account?.display ?? '등록해 두면 새 여행에 자동으로 들어가요',
                    onTap: () => _editAccount(context, ref, profile, name),
                  ),
                  _Row(
                    leading: const Icon(AppIcons.bell,
                        color: AppColors.textSub),
                    title: '알림',
                    subtitle: _notifySummary(profile),
                    onTap: () => context.push('/notifications'),
                  ),
                ]),
              ]),
            ),
            // 버전은 화면 맨 아래(떠 있는 바 바로 위)에 둔다. 내용이 길어지면 그 뒤로 밀린다.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Container(
                alignment: Alignment.bottomCenter,
                padding: EdgeInsets.fromLTRB(
                    16, 32, 16, MediaQuery.paddingOf(context).bottom + 16),
                child: Text(version ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textHint)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = this.name;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.primaryLight, shape: BoxShape.circle),
                child: name == null
                    ? const Icon(AppIcons.userFill,
                        size: 28, color: AppColors.primaryDeep)
                    : Text(String.fromCharCode(name.runes.first),
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDeep)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name ?? '이름을 정해 주세요',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: name == null
                                ? AppColors.textHint
                                : AppColors.text)),
                    const SizedBox(height: 2),
                    const Text('동행자에게 보이는 내 이름',
                        style:
                            TextStyle(fontSize: 13, color: AppColors.textHint)),
                  ],
                ),
              ),
              const Icon(AppIcons.edit,
                  size: 20, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
      {required this.leading, required this.title, this.subtitle, this.onTap});

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(width: 32, child: Center(child: leading)),
      title: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
      trailing: onTap == null
          ? null
          : const Icon(AppIcons.chevronRight,
              size: 20, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}
