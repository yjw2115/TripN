import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/features/notify/data/push_service.dart';
import 'package:travelen/features/notify/data/trip_notice_sender.dart';
import 'package:travelen/features/notify/domain/trip_notice.dart';
import 'package:travelen/features/notify/presentation/notification_settings_screen.dart';
import 'package:travelen/features/trip/data/trip_repository.dart';
import 'package:travelen/core/ui/controls.dart';

class _FakeUser implements User {
  @override
  String get uid => 'u';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePush implements PushService {
  _FakePush(this.current);

  PushPermission current;
  final setUpFor = <String>[];
  List<String> hidden = const [];
  final arrivals = StreamController<TripNotice>.broadcast();

  @override
  String? get token => tokenState.value == TokenState.saved ? 'my-token' : null;

  @override
  Future<List<String>> hiddenPlaces() async => hidden;

  @override
  Future<void> presentInForeground() async {}

  @override
  bool get showsOwnForegroundNotice => true;

  @override
  final tokenState = ValueNotifier(TokenState.none);

  @override
  String? lastError;

  @override
  Future<PushPermission> permission() async => current;

  /// 시스템 권한 창에서 "허용"을 누른다.
  @override
  Future<PushPermission> requestPermission() async =>
      current = PushPermission.allowed;

  @override
  Future<void> setUp(String uid, {bool ask = false}) async {
    setUpFor.add(uid);
    if (current == PushPermission.allowed) tokenState.value = TokenState.saved;
  }

  @override
  Stream<TripNotice> get onForeground => arrivals.stream;

  @override
  Stream<TripNotice> get onOpened => const Stream.empty();

  @override
  Future<TripNotice?> initialNotice() async => null;

  @override
  void dispose() {}
}

void main() {
  late FakeFirebaseFirestore db;

  /// 서버(sendTestNotice)가 남길 결과. null이면 테스트 알림을 보내지 않은 것처럼 아무것도 남기지 않는다.
  late Map<String, Object?>? serverResult;
  late List<Map<String, Object?>> tests;

  setUpAll(() => initializeDateFormatting('ko'));

  setUp(() {
    db = FakeFirebaseFirestore();
    serverResult = {'ok': true};
    tests = [];
  });

  Widget app(_FakePush push) => ProviderScope(
        overrides: [
          tripRepositoryProvider.overrideWithValue(TripRepository(db)),
          currentUserProvider.overrideWith((ref) async => _FakeUser()),
          pushServiceProvider.overrideWithValue(push),
          tripNoticeSenderProvider.overrideWithValue(TripNoticeSender((name, data) async {
            tests.add(data);
            final result = serverResult;
            if (result == null) return;
            await db.doc('users/u').set({
              'pushTest': {...result, 'at': DateTime.now().toUtc().toIso8601String()},
            }, SetOptions(merge: true));
          })),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      );

  testWidgets('turns notifications on when they were never asked for',
      (tester) async {
    final push = _FakePush(PushPermission.notAsked);
    await tester.pumpWidget(app(push));
    await tester.pumpAndSettle();
    expect(find.text('이 휴대폰에서 알림이 꺼져 있어요'), findsOneWidget);

    await tester.tap(find.text('알림 켜기'));
    await tester.pumpAndSettle();

    expect(find.text('이 휴대폰에서 알림이 꺼져 있어요'), findsNothing);
    expect(push.setUpFor, ['u']);
    expect(find.text('이 기기에서 알림을 받을 수 있어요'), findsOneWidget);
  });

  testWidgets('shows why this device could not be registered and retries',
      (tester) async {
    final push = _FakePush(PushPermission.allowed);
    await tester.pumpWidget(app(push));
    await tester.pumpAndSettle();
    push
      ..lastError = '[firebase_messaging/unknown] API key not valid'
      ..tokenState.value = TokenState.failed;
    await tester.pump();

    expect(find.text('이 기기를 알림에 등록하지 못했어요'), findsOneWidget);
    expect(find.textContaining('API key not valid'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('이 기기에서 알림을 받을 수 있어요'), findsOneWidget);
  });

  testWidgets('after a refusal it points to the phone settings', (tester) async {
    await tester.pumpWidget(app(_FakePush(PushPermission.denied)));
    await tester.pumpAndSettle();

    expect(find.textContaining('여행N > 알림에서 켜 주세요'), findsOneWidget);
    expect(find.text('알림 켜기'), findsNothing);
  });

  group('notification check', () {
    testWidgets('warns when the phone hides this app\'s banners',
        (tester) async {
      final push = _FakePush(PushPermission.allowed)..hidden = ['배너', '잠금 화면'];
      await tester.pumpWidget(app(push));
      await tester.pumpAndSettle();

      expect(find.textContaining('배너·잠금 화면 표시가 꺼져 있어서'), findsOneWidget);
    });

    testWidgets('sends a test to this device and shows that it arrived',
        (tester) async {
      final push = _FakePush(PushPermission.allowed);
      await tester.pumpWidget(app(push));
      await tester.pumpAndSettle();

      await tester.tap(find.text('테스트 알림 보내기'));
      await tester.pumpAndSettle();
      expect(tests.single, {'token': 'my-token', 'delaySeconds': 5});
      expect(find.textContaining('알림 서버가 이 기기로 보냈어요'), findsOneWidget);

      push.arrivals.add(const TripNotice(tripId: '', type: NoticeType.test));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('이 기기에 도착했어요'), 200);
      expect(find.text('이 기기에 도착했어요'), findsOneWidget);
    });

    testWidgets('explains an APNs key problem reported by FCM', (tester) async {
      serverResult = {'ok': false, 'code': 'messaging/third-party-auth-error'};
      await tester.pumpWidget(app(_FakePush(PushPermission.allowed)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('테스트 알림 보내기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Apple 알림 서버가 거절했어요'), findsOneWidget);
    });
  });

  testWidgets('each kind starts on and can be turned off for this account',
      (tester) async {
    await tester.pumpWidget(app(_FakePush(PushPermission.allowed)));
    await tester.pumpAndSettle();
    final switches = find.byType(SwitchRow);
    expect(tester.widgetList<SwitchRow>(switches).map((s) => s.value),
        [true, true]);

    await tester.tap(find.text('동행자 지출'));
    await tester.pumpAndSettle();

    expect((await db.doc('users/u').get()).data()?['notify'], {'expense': false});
    expect(tester.widgetList<SwitchRow>(switches).map((s) => s.value),
        [false, true]);
  });
}
