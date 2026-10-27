import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/pressable.dart';
import 'features/notify/data/push_service.dart';
import 'features/notify/domain/trip_notice.dart';
import 'features/receipt/presentation/capture.dart';
import 'features/receipt/presentation/scan_guide.dart';
import 'features/trip/presentation/members_sheet.dart';
import 'features/trip/presentation/trip_sheets.dart';
import 'features/trip/presentation/widgets/trip_widgets.dart';
import 'core/theme/app_icons.dart';
import 'core/ui/toast.dart';

/// 지출·통계·MY 세 탭을 담고, 화면 아래에 떠 있는 바를 둔다.
///
/// 바: [여행 이름 · 인원 | 지출 | 통계 | MY]  (스캔)
/// 가운데 점 왼쪽은 여행 전환 시트, 오른쪽은 동행자 시트를 연다. 탭은 화면 이동만, 동그라미는 영수증 스캔.
/// 분석·확인·정산 같은 화면은 이 셸 밖(루트 내비게이터)에 있어서 열리면 바를 덮는다.
///
/// 푸시 알림도 여기서 받는다: 누르면 그 여행으로 가고, 앱을 보고 있을 때 오면 스낵바로 보여준다.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _subscriptions = <StreamSubscription<TripNotice>>[];

  /// 앱으로 돌아올 때 이 기기 토큰을 아직 저장하지 못했으면 다시 해 본다
  /// (권한을 휴대폰 설정에서 켰거나, iOS가 APNs 토큰을 늦게 줬을 때).
  late final _lifecycle = AppLifecycleListener(onResume: _retryPush);

  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    _lifecycle;
    final push = ref.read(pushServiceProvider);
    push.presentInForeground().catchError(
        (Object e) => debugPrint('Foreground presentation failed: $e'));
    _subscriptions
      ..add(push.onOpened.listen(_open))
      ..add(push.onForeground.listen(_show));
    push.initialNotice().then((notice) {
      if (notice != null && mounted) _open(notice);
    }, onError: (Object e) => debugPrint('Initial notice failed: $e'));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  void _retryPush() {
    final push = ref.read(pushServiceProvider);
    final uid = ref.read(currentUserProvider).value?.uid;
    if (uid == null || push.tokenState.value == TokenState.saved) return;
    push.setUp(uid).catchError((Object e) => debugPrint('Push retry failed: $e'));
  }

  /// 알림의 여행으로 바꾸고 지출 탭으로 간다. 정산 알림이면 정산 화면까지 연다.
  /// 테스트 알림은 갈 곳이 없다.
  Future<void> _open(TripNotice notice) async {
    if (notice.type == NoticeType.test) return;
    final router = GoRouter.of(context);
    final repo = ref.read(tripRepositoryProvider);
    final user = await ref.read(currentUserProvider.future);
    if (ref.read(currentTripProvider).value?.id != notice.tripId) {
      // 기기에 먼저 반영돼서 기다리지 않아도 바로 바뀐다.
      unawaited(repo
          .selectTrip(user.uid, notice.tripId)
          .catchError((Object e) => debugPrint('Select trip failed: $e')));
    }
    router.go('/');
    if (notice.opensSettlement) router.push('/settlement');
  }

  /// 앱을 보고 있을 때 Android는 시스템 알림이 뜨지 않아서 스낵바로 알린다.
  /// iOS는 시스템 배너가 뜨고, 누르면 [_open]으로 온다.
  void _show(TripNotice notice) {
    if (!mounted || !ref.read(pushServiceProvider).showsOwnForegroundNotice) {
      return;
    }
    showToast(
      context,
      notice.body.isEmpty ? notice.title : notice.body,
      kind: ToastKind.info,
      actionLabel: notice.type == NoticeType.test ? null : '보기',
      onAction: () => _open(notice),
    );
  }

  /// 첫 안내가 가리킬 스캔 버튼.
  final _scanKey = GlobalKey();

  /// 안내를 닫았다. 저장이 끝나기 전에도 바로 사라지게 한다.
  bool _guideClosed = false;

  Future<void> _closeGuide({bool scan = false}) async {
    setState(() => _guideClosed = true);
    final uid = ref.read(currentUserProvider).value?.uid;
    if (uid != null) {
      reportWriteErrors(
          context, ref.read(tripRepositoryProvider).markScanGuideSeen(uid));
    }
    if (scan) await captureReceipt(context, ref, fromGallery: false);
  }

  @override
  Widget build(BuildContext context) {
    // 새 여행·참여·초대 때 MY 탭을 열지 않았어도 내 이름·계좌를 바로 쓸 수 있게 미리 불러 둔다.
    // 처음 쓰는 사람에게는 스캔 버튼이 무엇인지 한 번 알려준다.
    final seenGuide =
        ref.watch(profileProvider.select((p) => p.value?.seenScanGuide));
    ref.watch(pushRegistrationProvider);
    return Stack(
      children: [
        Scaffold(
          extendBody: true,
          body: shell,
          bottomNavigationBar: _FloatingBar(
            index: shell.currentIndex,
            scanKey: _scanKey,
            onTab: (i) {
              if (i != shell.currentIndex) HapticFeedback.selectionClick();
              // 이미 보던 탭을 다시 누르면 그 탭의 처음 화면으로.
              shell.goBranch(i, initialLocation: i == shell.currentIndex);
            },
          ),
        ),
        if (seenGuide == false && !_guideClosed)
          ScanGuide(
            targetKey: _scanKey,
            onClose: () => _closeGuide(),
            onScan: () => _closeGuide(scan: true),
          ),
      ],
    );
  }
}

class _FloatingBar extends ConsumerWidget {
  const _FloatingBar(
      {required this.index, required this.scanKey, required this.onTab});

  final int index;
  final GlobalKey scanKey;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(currentTripProvider).value;
    final memberCount = ref.watch(membersProvider).value?.length;
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 64,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: AppColors.border, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TripChip(
                        name: trip?.name ?? '여행N',
                        memberCount: memberCount,
                        onTrip: trip == null
                            ? null
                            : () => showTripSwitcher(context, ref),
                        onMembers: () => showMembersSheet(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _Tabs(index: index, onTab: onTab),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _ScanButton(
                key: scanKey,
                onTap: () => captureReceipt(context, ref, fromGallery: false)),
          ],
        ),
      ),
    );
  }
}

/// 회색 캡슐. 가운데에 "여행 이름 · N명".
/// 가운데 점보다 왼쪽(빈 곳 포함)을 누르면 여행 전환, 오른쪽을 누르면 동행자.
class _TripChip extends StatefulWidget {
  const _TripChip(
      {required this.name,
      required this.memberCount,
      required this.onTrip,
      required this.onMembers});

  final String name;
  final int? memberCount;
  final VoidCallback? onTrip;
  final VoidCallback onMembers;

  @override
  State<_TripChip> createState() => _TripChipState();
}

class _TripChipState extends State<_TripChip> {
  /// 왼쪽·오른쪽을 가르는 가운데 점.
  final _dot = GlobalKey();

  /// 방금 누른 곳이 점의 오른쪽이다.
  bool _members = false;

  void _down(PointerDownEvent event) {
    final dot = _dot.currentContext?.findRenderObject() as RenderBox?;
    _members = dot != null &&
        event.position.dx >= dot.localToGlobal(dot.size.center(Offset.zero)).dx;
  }

  void _tap() {
    final members = _members;
    // 화면 낭독기로 누르면 손가락이 닿지 않으니 다음 탭은 다시 여행 쪽에서 시작한다.
    _members = false;
    members ? widget.onMembers() : widget.onTrip?.call();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.memberCount;
    final name = widget.name;
    const countStyle = TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSub);
    return Listener(
      onPointerDown: _down,
      child: Pressable(
        scale: 0.97,
        onTap: widget.onTrip == null && count == null ? null : _tap,
        semanticLabel: '여행 바꾸기',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const ShapeDecoration(
            color: AppColors.background,
            shape: StadiumBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: Center(
                  widthFactor: 1,
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                ),
              ),
              if (count != null)
                Semantics(
                  button: true,
                  label: '동행자 $count명',
                  onTap: widget.onMembers,
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: Center(
                      widthFactor: 1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('·', key: _dot, style: countStyle),
                          Text(' $count명', style: countStyle),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지출·통계·MY 탭. 고른 탭 뒤로 연한 초록 캡슐이 미끄러진다.
/// 탭이 셋이라 여행 이름 자리를 남기려고 조금 좁게 둔다.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onTab});

  static const _width = 52.0;
  static const _items = [
    (label: '지출', icon: AppIcons.receipt, selected: AppIcons.receiptFill),
    (label: '통계', icon: AppIcons.stats, selected: AppIcons.statsFill),
    (label: 'MY', icon: AppIcons.user, selected: AppIcons.userFill),
  ];

  final int index;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width * _items.length,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: _width * index,
            top: 0,
            bottom: 0,
            width: _width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // 흰 바 위에서 primaryLight는 너무 옅어서 primary를 섞는다.
                color: AppColors.primary.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(26),
              ),
            ),
          ),
          Row(
            children: [
              for (final (i, item) in _items.indexed)
                Semantics(
                  selected: i == index,
                  button: true,
                  child: Pressable(
                    onTap: () => onTab(i),
                    child: SizedBox(
                      width: _width,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(i == index ? item.selected : item.icon,
                              size: 24,
                              color: i == index
                                  ? AppColors.onPrimary
                                  : AppColors.textHint),
                          const SizedBox(height: 2),
                          Text(item.label,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: i == index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: i == index
                                      ? AppColors.onPrimary
                                      : AppColors.textHint)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 영수증 스캔. 어느 탭에서든 한 번 누르면 문서 스캐너가 열린다.
/// 앱에서 가장 많이 쓰는 버튼이라 진한 초록에 흰 테두리로 바 위에서 도드라지게 한다.
class _ScanButton extends StatelessWidget {
  const _ScanButton({super.key, required this.onTap});

  static const size = 68.0;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: '영수증 스캔',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryDeep,
          border: Border.all(color: AppColors.surface, width: 3),
          boxShadow: [
            BoxShadow(
                color: AppColors.primaryDeep.withValues(alpha: 0.38),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        // 스캔 테두리 안에 영수증: "영수증을 찍는다"
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Icon(AppIcons.scan, size: 38, color: Colors.white),
            Icon(AppIcons.receiptFill, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
