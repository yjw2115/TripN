import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';
import 'widgets/trip_widgets.dart';

enum _Step { code, confirm, pick }

/// 초대 코드 입력 → 여행 확인 → 참여 → 이 여행에서 누구인지 고르기.
/// 멤버 목록은 참여한 뒤에야 읽을 수 있어서, 고르기는 참여 다음에 한다.
/// 초대 링크로 열리면 [initialCode]로 코드 입력을 건너뛰고 바로 여행을 찾는다.
class JoinTripScreen extends ConsumerStatefulWidget {
  const JoinTripScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends ConsumerState<JoinTripScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  _Step _step = _Step.code;
  InviteInfo? _invite;
  String? _error;
  bool _busy = false;

  /// 고른 동행자. 실수로 새 사람이 되지 않게 처음에는 아무것도 고르지 않는다.
  String? _guestId;
  bool _newPerson = false;

  @override
  void initState() {
    super.initState();
    final code = normalizeInviteCode(widget.initialCode ?? '');
    if (code != null) {
      _code.text = code;
      WidgetsBinding.instance.addPostFrameCallback((_) => _find());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  TripRepository get _repo => ref.read(tripRepositoryProvider);

  Future<void> _find() async {
    final code = normalizeInviteCode(_code.text);
    if (code == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 링크로 앱이 처음 열렸을 때는 아직 로그인 중일 수 있다 (초대 문서를 읽으려면 로그인이 필요하다).
      await ref.read(currentUserProvider.future);
      final invite = await _repo.findInvite(code);
      if (!mounted) return;
      if (invite == null) {
        setState(() => _error = '코드를 찾지 못했어요. 다시 확인해 주세요.');
        return;
      }
      final myTrips = await ref.read(myTripsProvider.future);
      if (!mounted) return;
      if (myTrips.any((t) => t.id == invite.tripId)) {
        final user = await ref.read(currentUserProvider.future);
        if (!mounted) return;
        reportWriteErrors(context, _repo.selectTrip(user.uid, invite.tripId));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("이미 참여한 '${invite.tripName}' 여행이에요")));
        context.go('/');
        return;
      }
      setState(() {
        _invite = invite;
        _step = _Step.confirm;
      });
    } on FirebaseException catch (e) {
      debugPrint('Find invite failed: $e');
      if (mounted) {
        setState(() => _error = e.code == 'unavailable'
            ? '인터넷에 연결되지 않았어요.'
            : '코드를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final invite = _invite!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(currentUserProvider.future);
      await _repo.join(invite, user.uid);
      if (mounted) setState(() => _step = _Step.pick);
    } on FirebaseException catch (e) {
      debugPrint('Join failed: $e');
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? '초대 코드가 바뀌었거나 더 이상 쓸 수 없어요.'
            : '참여하지 못했어요. 인터넷 연결을 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final invite = _invite!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(currentUserProvider.future);
      final guestId = _guestId;
      if (guestId != null) {
        await _repo.claimGuest(
            tripId: invite.tripId, guestId: guestId, uid: user.uid);
      } else {
        await _repo.renameMember(invite.tripId, user.uid, _name.text.trim());
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("'${invite.tripName}' 여행에 참여했어요")));
      context.go('/');
    } on FirebaseException catch (e) {
      debugPrint('Finish join failed: $e');
      if (mounted) setState(() => _error = '저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 링크로 바로 열리면 홈 화면이 없어서 아무도 내 여행 목록을 지켜보지 않는다.
    // Riverpod은 지켜보는 쪽이 없는 provider를 멈춰 두므로, 이미 참여한 여행인지 볼 수 있게 여기서 지켜본다.
    ref.watch(myTripsProvider);
    final guests = _step == _Step.pick
        ? (ref.watch(tripMembersProvider(_invite!.tripId)).value ?? const <Member>[])
            .where((m) => m.isGuest)
            .toList()
        : const <Member>[];
    final asksName = _newPerson || guests.isEmpty;
    final (body, label, onPressed) = switch (_step) {
      _Step.code => (
          _codeStep(),
          '다음',
          normalizeInviteCode(_code.text) == null ? null : _find,
        ),
      _Step.confirm => (_confirmStep(), '참여하기', _join),
      _Step.pick => (
          _pickStep(guests, asksName),
          '완료',
          _guestId != null || (asksName && _name.text.trim().isNotEmpty)
              ? _finish
              : null,
        ),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('초대 코드로 참여'),
        // 링크로 바로 열려서 돌아갈 화면이 없으면 홈으로 간다.
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.go('/'),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          body,
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 14, color: AppColors.danger)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _busy ? null : onPressed,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.textHint))
                : Text(label),
          ),
        ),
      ),
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('초대 코드를 입력해 주세요', '동행자에게 받은 6자리 코드예요.'),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
            LengthLimitingTextInputFormatter(12),
          ],
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 6),
          decoration: const InputDecoration(hintText: 'K7Q2MX'),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _find(),
        ),
      ],
    );
  }

  Widget _confirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('이 여행에 참여할까요?', '참여하면 동행자들과 지출 기록을 함께 보고 쓸 수 있어요.'),
        const SizedBox(height: 24),
        SectionCard(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.luggage_outlined,
                  color: AppColors.primaryDeep),
            ),
            title: Text(_invite!.tripName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ]),
      ],
    );
  }

  Widget _pickStep(List<Member> guests, bool asksName) {
    final nameField = TextField(
      controller: _name,
      autofocus: guests.isEmpty,
      maxLength: nameMaxLength,
      decoration: const InputDecoration(hintText: '예) 지민', counterText: ''),
      onChanged: (_) => setState(() {}),
    );
    if (guests.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('동행자에게 보일 이름을 정해 주세요', '나중에 여행 설정에서 바꿀 수 있어요.'),
          const SizedBox(height: 24),
          nameField,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('이 여행에서 누구세요?',
            '이름으로 먼저 추가된 사람이라면 고르세요. 그동안의 기록이 그대로 이어져요.'),
        const SizedBox(height: 16),
        SectionCard(children: [
          for (final g in guests)
            _Choice(
              leading: MemberAvatar(g),
              label: g.name,
              selected: _guestId == g.id,
              onTap: () => setState(() {
                _guestId = g.id;
                _newPerson = false;
              }),
            ),
          _Choice(
            leading: const CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.background,
              child: Icon(Icons.person_add_alt_1_outlined,
                  size: 20, color: AppColors.textSub),
            ),
            label: '목록에 없어요',
            selected: _newPerson,
            onTap: () => setState(() {
              _guestId = null;
              _newPerson = true;
            }),
          ),
          if (asksName) ...[
            const SizedBox(height: 4),
            nameField,
            const SizedBox(height: 8),
          ],
        ]),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(body,
            style: const TextStyle(fontSize: 15, color: AppColors.textSub)),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? AppColors.primaryDeep : AppColors.border,
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}
