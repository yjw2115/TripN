import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../trip/data/trip_repository.dart';
import '../domain/trip_notice.dart';

enum PushPermission {
  /// 아직 묻지 않았다.
  notAsked,
  allowed,

  /// 거절했다. 다시 물을 수 없어서 휴대폰 설정에서 켜야 한다.
  denied,
}

/// 이 기기 토큰을 저장했는지. 알림이 오지 않을 때 MY → 알림에서 까닭을 보여준다.
enum TokenState {
  /// 아직 시도하지 않았거나 알림 권한이 없다.
  none,

  /// iOS가 아직 APNs 토큰을 주지 않았다. 나중에라도 받으면 저장한다.
  waitingForApns,
  saved,
  failed,
}

/// 이 기기의 푸시 알림: 권한, FCM 토큰, 받은 알림.
/// 토큰은 users/{uid}.fcmTokens에 모아 두고, Functions가 동행자에게 보낼 때 읽는다.
class PushService {
  PushService(this._repo);

  final TripRepository _repo;
  StreamSubscription<String>? _refresh;

  /// 이번 실행에서 저장한 토큰. 같은 토큰을 또 쓰지 않는다.
  String? _saved;

  final tokenState = ValueNotifier(TokenState.none);

  /// [TokenState.failed]일 때 무엇이 잘못됐는지.
  String? lastError;

  /// 이 기기 토큰 (저장한 뒤에만). 테스트 알림을 이 기기로만 보낼 때 쓴다.
  String? get token => _saved;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  Future<PushPermission> permission() async =>
      _permissionOf((await _fm.getNotificationSettings()).authorizationStatus);

  /// 시스템 권한 창을 띄운다. 이미 답했으면 창 없이 그 답을 돌려준다.
  Future<PushPermission> requestPermission() async =>
      _permissionOf((await _fm.requestPermission()).authorizationStatus);

  /// 알림이 허락돼 있으면 이 기기 토큰을 저장한다. [ask]면 아직 묻지 않은 권한을 먼저 묻는다.
  /// 여러 번 불러도 된다 (앱으로 돌아올 때마다 아직 저장하지 못했으면 다시 해 본다).
  Future<void> setUp(String uid, {bool ask = false}) async {
    var status = await permission();
    if (status == PushPermission.notAsked && ask) {
      status = await requestPermission();
    }
    if (status != PushPermission.allowed) {
      tokenState.value = TokenState.none;
      return;
    }
    // 토큰이 늦게 나와도 놓치지 않게 먼저 듣는다. iOS는 권한을 막 받은 직후 APNs 토큰이
    // 몇 초 넘게 걸리기도 하는데, 그 뒤에 나오는 FCM 토큰은 여기로 온다.
    // ignore: deprecated_member_use
    _refresh ??= _fm.onTokenRefresh.listen((t) => _save(uid, t).catchError(_fail));
    try {
      final token = await _token();
      if (token == null) {
        tokenState.value = TokenState.waitingForApns;
        return;
      }
      await _save(uid, token);
    } catch (e) {
      _fail(e);
      rethrow;
    }
  }

  Future<void> _save(String uid, String token) async {
    if (token != _saved) await _repo.addPushToken(uid, token);
    _saved = token;
    lastError = null;
    tokenState.value = TokenState.saved;
  }

  void _fail(Object e) {
    lastError = '$e';
    tokenState.value = TokenState.failed;
  }

  /// iOS는 APNs 토큰이 생긴 뒤에야 FCM 토큰을 받을 수 있어서, 권한을 막 받았으면 잠깐 기다린다.
  /// 그래도 없으면 null (나중에 생기면 onTokenRefresh로 받는다).
  ///
  /// 17.0.0은 토큰 대신 설치 ID(register/onRegistered)를 권하지만, Functions의 firebase-admin(13)은
  /// 아직 설치 ID로 보내지 못해서 FCM 토큰을 쓴다.
  Future<String?> _token() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var i = 0; i < 10 && await _fm.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (await _fm.getAPNSToken() == null) return null;
    }
    // ignore: deprecated_member_use
    return _fm.getToken();
  }

  /// 알림이 와도 보이지 않게 휴대폰 설정에서 꺼 둔 곳 (iOS의 배너·알림 센터·잠금 화면).
  /// 비어 있으면 문제없다. Android는 늘 비어 있다.
  Future<List<String>> hiddenPlaces() async {
    final s = await _fm.getNotificationSettings();
    return [
      if (s.alert == AppleNotificationSetting.disabled) '배너',
      if (s.notificationCenter == AppleNotificationSetting.disabled) '알림 센터',
      if (s.lockScreen == AppleNotificationSetting.disabled) '잠금 화면',
    ];
  }

  /// iOS는 앱을 보고 있을 때도 시스템이 배너를 띄우게 한다 (notification_class 앱과 같다).
  /// Android는 시스템이 띄우지 않아서 앱이 스낵바로 보여준다 ([showsOwnForegroundNotice]).
  Future<void> presentInForeground() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await _fm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true);
  }

  /// 앱을 보고 있을 때 온 알림을 앱이 직접 보여줘야 하는지 (iOS는 시스템 배너가 뜬다).
  bool get showsOwnForegroundNotice =>
      defaultTargetPlatform != TargetPlatform.iOS;

  /// 앱을 보고 있을 때 온 알림. iOS는 시스템 배너도 함께 뜬다 ([presentInForeground]).
  Stream<TripNotice> get onForeground =>
      FirebaseMessaging.onMessage.expand((m) => [?_notice(m)]);

  /// 백그라운드에서 알림을 눌러 앱으로 돌아왔다.
  Stream<TripNotice> get onOpened =>
      FirebaseMessaging.onMessageOpenedApp.expand((m) => [?_notice(m)]);

  /// 꺼져 있던 앱을 알림을 눌러 열었다.
  Future<TripNotice?> initialNotice() async {
    final message = await _fm.getInitialMessage();
    return message == null ? null : _notice(message);
  }

  void dispose() {
    _refresh?.cancel();
    tokenState.dispose();
  }

  static TripNotice? _notice(RemoteMessage message) => TripNotice.fromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body);

  static PushPermission _permissionOf(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          PushPermission.allowed,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently =>
          PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
      };
}
