import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../domain/trip.dart';
import 'widgets/account_sheet.dart';
import 'widgets/bank_picker.dart';
import 'widgets/trip_widgets.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/toast.dart';
import '../../../core/ui/app_dialog.dart';
import '../../../core/ui/controls.dart';

/// 플로팅 바의 인원을 누르면 여는 동행자 시트. 동행자를 추가·수정하고 초대 코드를 보낸다.
Future<void> showMembersSheet(BuildContext context) =>
    showAppSheet<void>(context, (context) => const _MembersSheet());

class _MembersSheet extends ConsumerWidget {
  const _MembersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(currentTripProvider).value;
    final user = ref.watch(currentUserProvider).value;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    if (trip == null || user == null) {
      return const SizedBox(
          height: 200, child: Center(child: AppSpinner()));
    }
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
            child: Row(
              children: [
                Text('동행자 ${members.length}명',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addGuest(context, ref, trip, user.uid),
                  icon: const Icon(AppIcons.userPlus, size: 18),
                  label: const Text('추가'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final m in members)
                  _MemberRow(
                    member: m,
                    isMe: m.uid == user.uid,
                    onTap: () => _editMember(context, ref, trip, m),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 16),
                  child: Text(
                    '앱을 쓰지 않는 사람도 이름만으로 추가해서 같이 정산할 수 있어요.',
                    style: TextStyle(fontSize: 13, color: AppColors.textHint),
                  ),
                ),
                _InviteCard(trip: trip, uid: user.uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addGuest(
      BuildContext context, WidgetRef ref, Trip trip, String uid) async {
    final name = await showTextSheet(context,
        title: '동행자 추가', initial: '', hint: '이름 (예: 민수)', maxLength: nameMaxLength);
    if (name == null || name.isEmpty || !context.mounted) return;
    reportWriteErrors(
        context,
        ref
            .read(tripRepositoryProvider)
            .addGuest(tripId: trip.id, name: name, uid: uid));
  }

  /// 이름과 계좌는 누구나 고칠 수 있다. 지우기는 이름만 있는 동행자이고,
  /// 결제자나 품목을 같이 먹은 사람으로 기록되지 않았을 때만.
  Future<void> _editMember(
      BuildContext context, WidgetRef ref, Trip trip, Member member) async {
    final action = await showAppSheet<_MemberAction>(
      context,
      (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.edit),
              title: const Text('이름 바꾸기'),
              onTap: () => Navigator.pop(context, _MemberAction.rename),
            ),
            ListTile(
              leading: member.account == null
                  ? const Icon(AppIcons.bank)
                  : BankIcon(member.account!.bank, size: 28),
              title: Text(member.account == null ? '받을 계좌 등록' : '받을 계좌 수정'),
              subtitle: member.account == null
                  ? null
                  : Text(member.account!.display),
              onTap: () => Navigator.pop(context, _MemberAction.account),
            ),
            if (member.isGuest)
              ListTile(
                leading:
                    const Icon(AppIcons.trash, color: AppColors.danger),
                title: const Text('삭제',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(context, _MemberAction.delete),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final repo = ref.read(tripRepositoryProvider);
    switch (action) {
      case _MemberAction.rename:
        final name = await showTextSheet(context,
            title: '이름 바꾸기', initial: member.name, maxLength: nameMaxLength);
        if (name == null || name.isEmpty || name == member.name || !context.mounted) {
          return;
        }
        reportWriteErrors(context, repo.renameMember(trip.id, member.id, name));
      case _MemberAction.account:
        await editAccount(context, ref, trip.id, member);
      case _MemberAction.delete:
        await _deleteGuest(context, ref, trip, member);
    }
  }

  Future<void> _deleteGuest(
      BuildContext context, WidgetRef ref, Trip trip, Member member) async {
    final expenses = ref.read(expensesProvider).value ?? const [];
    // 스낵바는 시트에 가려서 대화상자로 알린다.
    if (expenses.any((e) => e.involves(member.id))) {
      await showNoticeDialog(context,
          body: '${member.name}님이 결제했거나 같이 먹은 품목이 있어서 삭제할 수 없어요.');
      return;
    }
    final sharedIds = [
      for (final e in expenses)
        if (e.participantIds.contains(member.id)) e.id,
    ];
    final confirmed = await confirmDialog(context,
        title: '${member.name}님을 삭제할까요?',
        body: sharedIds.isEmpty
            ? '동행자 목록에서 빠져요.'
            : '함께 쓴 지출 ${sharedIds.length}건에서도 빠지고, 정산을 다시 계산해요.',
        confirmLabel: '삭제',
        destructive: true);
    if (!confirmed || !context.mounted) return;
    final expenseRepo = ref.read(expenseRepositoryProvider);
    final repo = ref.read(tripRepositoryProvider);
    reportWriteErrors(
        context,
        Future.wait([
          if (sharedIds.isNotEmpty)
            expenseRepo.removeParticipant(trip.id, member.id, sharedIds),
          repo.deleteMember(trip.id, member.id),
        ]));
  }
}

enum _MemberAction { rename, account, delete }

class _MemberRow extends StatelessWidget {
  const _MemberRow(
      {required this.member, required this.isMe, required this.onTap});

  final Member member;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bank = member.account?.bank ?? '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: MemberAvatar(member),
      title: Text(member.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          isMe
              ? (member.name == defaultMyName ? '나 · 눌러서 이름 정하기' : '나')
              : member.isGuest
                  ? '이름만 있는 동행자'
                  : '앱 사용 중',
          if (bank.isNotEmpty) bank,
        ].join(' · '),
        style: TextStyle(
            fontSize: 13,
            color: isMe ? AppColors.primaryDeep : AppColors.textHint),
      ),
      trailing: const Icon(AppIcons.chevronRight,
          size: 20, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.trip, required this.uid});

  final Trip trip;
  final String uid;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _busy = false;

  /// 코드를 복사했다는 표시. 스낵바는 시트에 가려서 복사 아이콘을 잠깐 체크로 바꾼다.
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  /// 동행자 앱에 '나'로 보이지 않게, 이름을 정하지 않았으면 MY 탭의 이름을 쓰거나 먼저 묻는다.
  Future<bool> _ensureMyName() async {
    final me = await ref.read(myMemberProvider.future);
    if (me == null || me.name != defaultMyName) return true;
    if (!mounted) return false;
    final name = ref.read(profileProvider).value?.name ??
        await showTextSheet(context,
            title: '동행자에게 보일 내 이름',
            initial: '',
            hint: '예) 지민',
            maxLength: nameMaxLength);
    if (name == null || name.isEmpty || !mounted) return false;
    reportWriteErrors(context,
        ref.read(tripRepositoryProvider).renameMember(widget.trip.id, me.id, name));
    return true;
  }

  Future<void> _invite() async {
    if (!await _ensureMyName() || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(tripRepositoryProvider)
          .ensureInviteCode(widget.trip.id, widget.uid);
      await SharePlus.instance.share(ShareParams(
        text: inviteMessage(widget.trip.name, code),
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      debugPrint('Invite failed: $e');
      if (mounted) {
        showToast(context, '초대 코드를 만들지 못했어요. 인터넷 연결을 확인해 주세요.',
            kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.trip.inviteCode;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('앱으로 함께 기록하기',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            '초대 코드를 보내면 동행자도 앱에서 이 여행에 지출을 기록할 수 있어요. '
            '이름으로 먼저 추가해 둔 사람은 들어와서 자기 이름을 고르면 돼요.',
            style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.4),
          ),
          if (code != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(code,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4)),
                  const Spacer(),
                  IconButton(
                    tooltip: '코드 복사',
                    icon: Icon(
                        _copied ? AppIcons.check : AppIcons.copy,
                        size: 20,
                        color: _copied
                            ? AppColors.primaryDeep
                            : AppColors.textSub),
                    onPressed: () => _copy(code),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _invite,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: AppSpinner(radius: 9, color: AppColors.textHint))
                : const Icon(AppIcons.share, size: 20),
            label: const Text('초대 코드 보내기'),
          ),
        ],
      ),
    );
  }
}
