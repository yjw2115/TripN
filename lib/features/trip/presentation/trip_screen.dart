import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_providers.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/exchange_rate.dart';
import '../../../core/theme/app_theme.dart';
import '../../receipt/presentation/widgets/edit_sheets.dart';
import '../domain/trip.dart';
import 'widgets/account_sheet.dart';
import 'widgets/bank_picker.dart';
import 'widgets/manual_rate_sheet.dart';
import 'widgets/trip_widgets.dart';

/// 지금 여행의 이름, 동행자, 초대 코드를 관리한다.
class TripScreen extends ConsumerWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(currentTripProvider).value;
    final user = ref.watch(currentUserProvider).value;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    if (trip == null || user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
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
              trailing: const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.textHint),
              onTap: () => _renameTrip(context, ref, trip),
            ),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: '동행자 ${members.length}명',
            trailing: TextButton.icon(
              onPressed: () => _addGuest(context, ref, trip, user.uid),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('추가'),
            ),
            children: [
              for (final m in members)
                _MemberRow(
                  member: m,
                  isMe: m.uid == user.uid,
                  onTap: () => _editMember(context, ref, trip, m),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '앱을 쓰지 않는 사람도 이름만으로 추가해서 같이 정산할 수 있어요.',
                  style: TextStyle(fontSize: 13, color: AppColors.textHint),
                ),
              ),
            ],
          ),
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
                    trailing: const Icon(Icons.edit_outlined,
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
          const SizedBox(height: 12),
          _InviteCard(trip: trip, uid: user.uid),
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
              leading: const Icon(Icons.edit_outlined),
              title: const Text('이름 바꾸기'),
              onTap: () => Navigator.pop(context, _MemberAction.rename),
            ),
            ListTile(
              leading: member.account == null
                  ? const Icon(Icons.account_balance_outlined)
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
                    const Icon(Icons.delete_outline, color: AppColors.danger),
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
    if (expenses.any((e) => e.involves(member.id))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${member.name}님이 결제했거나 같이 먹은 품목이 있어서 삭제할 수 없어요.')));
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
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(SnackBar(
          content: Text(isOwner
              ? "'${trip.name}' 여행을 삭제했어요"
              : "'${trip.name}' 여행에서 나왔어요")));
    } catch (e) {
      debugPrint('Delete or leave failed: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('처리하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.')));
    }
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: MemberAvatar(member),
      title: Text(member.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text(
        isMe
            ? (member.name == defaultMyName ? '나 · 눌러서 이름 정하기' : '나')
            : member.isGuest
                ? '이름만 있는 동행자'
                : '앱 사용 중',
        style: TextStyle(
            fontSize: 13,
            color: isMe ? AppColors.primaryDeep : AppColors.textHint),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
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

  /// 동행자 앱에 '나'로 보이지 않게, 이름을 정하지 않았으면 먼저 묻는다.
  Future<bool> _ensureMyName() async {
    final me = await ref.read(myMemberProvider.future);
    if (me == null || me.name != defaultMyName) return true;
    if (!mounted) return false;
    final name = await showTextSheet(context,
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('초대 코드를 만들지 못했어요. 인터넷 연결을 확인해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.trip.inviteCode;
    return SectionCard(
      title: '앱으로 함께 기록하기',
      children: [
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
              color: AppColors.background,
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
                  icon: const Icon(Icons.copy_rounded,
                      size: 20, color: AppColors.textSub),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('초대 코드를 복사했어요')));
                  },
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textHint))
              : const Icon(Icons.ios_share_rounded, size: 20),
          label: const Text('초대 코드 보내기'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
