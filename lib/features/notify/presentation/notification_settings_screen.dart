import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/widgets/trip_widgets.dart';
import '../data/push_service.dart';
import '../domain/trip_notice.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/controls.dart';

/// MY → 알림. 이 기기의 알림 권한과, 어떤 소식을 받을지 고른다.
/// 받을지 말지는 users/{uid}.notify에 두고 Functions가 보내기 전에 본다.
///
/// 알림이 오지 않을 때 디버거 없이 앱에서 까닭을 찾을 수 있게 "알림 점검"을 둔다:
/// 이 기기 등록(토큰), 휴대폰에서 꺼 둔 표시 방식, 이 기기로 보내는 테스트 알림.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  PushPermission? _permission;

  /// 휴대폰 설정에서 꺼 둔 알림 표시 방식 (iOS).
  List<String> _hidden = const [];

  bool _sending = false;
  DateTime? _sentAt;
  String? _sendError;

  /// 앱을 보고 있을 때 테스트 알림이 도착한 시각.
  DateTime? _arrivedAt;
  StreamSubscription<TripNotice>? _arrivals;

  /// 휴대폰 설정에서 알림을 켜고 돌아오면 다시 확인한다.
  late final _lifecycle = AppLifecycleListener(onResume: _check);

  @override
  void initState() {
    super.initState();
    _lifecycle;
    _arrivals = ref.read(pushServiceProvider).onForeground.listen((notice) {
      if (notice.type == NoticeType.test && mounted) {
        setState(() => _arrivedAt = DateTime.now());
      }
    });
    _check();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _arrivals?.cancel();
    super.dispose();
  }

  /// 권한을 다시 보고, 허락돼 있으면 이 기기를 등록한다 (이미 했으면 그대로).
  Future<void> _check() async {
    try {
      final push = ref.read(pushServiceProvider);
      final permission = await push.permission();
      final hidden = await push.hiddenPlaces();
      if (!mounted) return;
      setState(() {
        _permission = permission;
        _hidden = hidden;
      });
      if (permission == PushPermission.allowed) await _register();
    } catch (e) {
      debugPrint('Push permission check failed: $e');
    }
  }

  Future<void> _register() async {
    final user = await ref.read(currentUserProvider.future);
    try {
      await ref.read(pushServiceProvider).setUp(user.uid);
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
  }

  Future<void> _turnOn() async {
    final permission = await ref.read(pushServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _permission = permission);
    await _register();
  }

  /// 이 기기로 5초 뒤에 테스트 알림을 보낸다. 그사이 홈 화면으로 나가면 배너로 확인할 수 있다.
  Future<void> _sendTest(String token) async {
    setState(() {
      _sending = true;
      _sentAt = DateTime.now();
      _sendError = null;
      _arrivedAt = null;
    });
    try {
      await ref.read(tripNoticeSenderProvider).sendTest(token);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Test push failed: ${e.code} ${e.message}');
      if (mounted) setState(() => _sendError = _explainCallError(e.code));
    } catch (e) {
      debugPrint('Test push failed: $e');
      if (mounted) setState(() => _sendError = '보내지 못했어요 ($e)');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 보여줄 테스트 결과. 서버가 남긴 결과(앱이 백그라운드여도 남는다)를 먼저 본다.
  ({bool ok, String text})? _testResult(PushTest? last) {
    final sentAt = _sentAt;
    // 기기와 서버 시계가 조금 달라도 이번 테스트 결과로 본다.
    final fresh = last != null &&
        (sentAt == null ||
            last.at.isAfter(sentAt.subtract(const Duration(seconds: 30))));
    if (fresh) {
      final time = DateFormat('M월 d일 HH:mm:ss', 'ko').format(last.at.toLocal());
      return last.ok
          ? (ok: true, text: '알림 서버가 이 기기로 보냈어요 ($time)')
          : (ok: false, text: '${_explainPushError(last.code)} ($time)');
    }
    if (_sendError != null) return (ok: false, text: _sendError!);
    if (_sending) return (ok: true, text: '5초 뒤에 보내요…');
    return null;
  }

  Future<void> _set(NotifyTopic topic, bool on) async {
    final user = await ref.read(currentUserProvider.future);
    if (!mounted) return;
    reportWriteErrors(
        context, ref.read(tripRepositoryProvider).setNotify(user.uid, topic, on));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value ?? const Profile();
    final permission = _permission;
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (permission != null && permission != PushPermission.allowed) ...[
            _PermissionCard(permission: permission, onTurnOn: _turnOn),
            const SizedBox(height: 12),
          ],
          if (permission == PushPermission.allowed) ...[
            ValueListenableBuilder(
              valueListenable: ref.watch(pushServiceProvider).tokenState,
              builder: (context, state, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DeviceStatus(
                    state: state,
                    error: ref.read(pushServiceProvider).lastError,
                    onRetry: _register,
                  ),
                  const SizedBox(height: 12),
                  _TestCard(
                    hidden: _hidden,
                    token: state == TokenState.saved
                        ? ref.read(pushServiceProvider).token
                        : null,
                    sending: _sending,
                    result: _testResult(profile.pushTest),
                    arrivedAt: _arrivedAt,
                    onSend: _sendTest,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(children: [
            _Switch(
              title: '동행자 지출',
              subtitle: '앱을 쓰는 동행자가 지출을 기록하면 알려줘요',
              value: profile.notifyExpense,
              onChanged: (v) => _set(NotifyTopic.expense, v),
            ),
            _Switch(
              title: '정산',
              subtitle: '정산 요청을 받거나 동행자가 정산을 마치면 알려줘요',
              value: profile.notifySettlement,
              onChanged: (v) => _set(NotifyTopic.settlement, v),
            ),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              '내가 한 일은 알리지 않아요. 알림을 누르면 그 여행으로 바로 가요.',
              style: TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }
}

/// sendTestNotice를 부르지 못했을 때.
String _explainCallError(String code) => switch (code) {
      'failed-precondition' => '이 기기 토큰이 서버에 없어요. 위에서 다시 등록한 뒤 보내 주세요.',
      'not-found' || 'unimplemented' =>
        '서버에 테스트 기능이 아직 없어요. Functions를 배포해 주세요.',
      'unavailable' || 'deadline-exceeded' => '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
      _ => '보내지 못했어요 ($code)',
    };

/// FCM이 테스트 알림을 거절한 까닭. 코드는 firebase-admin의 messaging/* 오류 코드다.
String _explainPushError(String? code) => switch (code) {
      'messaging/third-party-auth-error' =>
        'Apple 알림 서버가 거절했어요. Firebase에 올린 APNs 키의 키 ID·팀 ID(7ZQN43985N)와, '
            'com.preper.tripN 앱에 올렸는지 확인해 주세요.',
      'messaging/registration-token-not-registered' =>
        '이 기기 토큰이 만료됐어요. 앱을 다시 열면 새로 등록해요.',
      'messaging/invalid-registration-token' || 'messaging/invalid-argument' =>
        '이 기기 토큰이 올바르지 않아요. 앱을 지웠다가 다시 설치해 보세요.',
      'messaging/mismatched-credential' || 'messaging/sender-id-mismatch' =>
        '이 기기 토큰이 다른 Firebase 프로젝트 것이에요.',
      _ => '알림 서버가 보내지 못했어요 (${code ?? '알 수 없음'})',
    };

/// 알림 점검: 휴대폰에서 꺼 둔 표시 방식과, 이 기기로 보내는 테스트 알림.
class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.hidden,
    required this.token,
    required this.sending,
    required this.result,
    required this.arrivedAt,
    required this.onSend,
  });

  final List<String> hidden;

  /// 이 기기 토큰. 아직 등록하지 못했으면 null이라 보낼 수 없다.
  final String? token;
  final bool sending;
  final ({bool ok, String text})? result;
  final DateTime? arrivedAt;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final token = this.token;
    final result = this.result;
    return SectionCard(
      title: '알림 점검',
      children: [
        if (hidden.isNotEmpty)
          _Line(
            icon: AppIcons.hidden,
            color: AppColors.warning,
            text: '이 휴대폰에서 ${hidden.join('·')} 표시가 꺼져 있어서 알림이 와도 보이지 않을 수 있어요. '
                '설정 > 여행N > 알림에서 켜 주세요.',
          ),
        const Text(
          '버튼을 누르면 5초 뒤에 이 기기로 테스트 알림을 보내요. 배너가 뜨면 정상이에요. '
          '홈 화면으로 나가서도 확인해 보세요.',
          style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.4),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: token == null || sending ? null : () => onSend(token),
          icon: const Icon(AppIcons.bellRinging, size: 20),
          label: const Text('테스트 알림 보내기'),
        ),
        if (result != null)
          _Line(
            icon: result.ok
                ? AppIcons.send
                : AppIcons.warning,
            color: result.ok ? AppColors.primaryDeep : AppColors.danger,
            text: result.text,
          ),
        if (arrivedAt != null)
          const _Line(
            icon: AppIcons.checkCircle,
            color: AppColors.primaryDeep,
            text: '이 기기에 도착했어요',
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.text, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// 알림 권한은 있는데 이 기기를 알림 받을 곳으로 등록했는지 (FCM 토큰을 저장했는지).
/// 알림이 오지 않을 때 여기서 까닭을 볼 수 있다.
class _DeviceStatus extends StatelessWidget {
  const _DeviceStatus(
      {required this.state, required this.error, required this.onRetry});

  final TokenState state;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (state) {
      TokenState.saved => (
          AppIcons.checkCircle,
          AppColors.primaryDeep,
          '이 기기에서 알림을 받을 수 있어요',
        ),
      TokenState.none => (
          AppIcons.hourglass,
          AppColors.textHint,
          '이 기기를 알림에 등록하는 중이에요',
        ),
      TokenState.waitingForApns => (
          AppIcons.offline,
          AppColors.warning,
          'Apple 알림 서버에서 아직 응답이 없어요. 인터넷 연결을 확인하고 다시 시도해 주세요.',
        ),
      TokenState.failed => (
          AppIcons.warning,
          AppColors.danger,
          '이 기기를 알림에 등록하지 못했어요',
        ),
    };
    final retry = state == TokenState.waitingForApns || state == TokenState.failed;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.text, height: 1.4)),
                if (state == TokenState.failed && error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(error!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                  ),
              ],
            ),
          ),
          if (retry)
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

/// 이 기기에서 알림이 꺼져 있을 때. 아직 묻지 않았으면 바로 켜고, 거절했으면 휴대폰 설정을 알려준다.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.permission, required this.onTurnOn});

  final PushPermission permission;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final denied = permission == PushPermission.denied;
    final settingsPath = defaultTargetPlatform == TargetPlatform.iOS
        ? '설정 > 여행N > 알림'
        : '설정 > 애플리케이션 > 여행N > 알림';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('이 휴대폰에서 알림이 꺼져 있어요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            denied
                ? '$settingsPath에서 켜 주세요.'
                : '켜 두면 동행자의 지출과 정산 소식을 바로 받아요.',
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSub, height: 1.4),
          ),
          if (!denied) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onTurnOn, child: const Text('알림 켜기')),
          ],
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchRow(
        title: title, subtitle: subtitle, value: value, onChanged: onChanged);
  }
}
