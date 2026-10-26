import 'package:flutter/foundation.dart';

import '../../settlement/domain/settlement.dart';

/// 정산 요청·정산 완료를 앱을 쓰는 동행자에게 알린다 (Functions의 sendTripNotice).
/// 지출 기록 알림은 Functions가 지출 문서가 생길 때 알아서 보낸다.
/// 알림은 덤이라 보내지 못해도 화면에 알리지 않는다. 테스트 알림만 실패를 돌려준다.
class TripNoticeSender {
  TripNoticeSender(this._call);

  /// Functions의 callable 함수 [name]을 부른다.
  final Future<void> Function(String name, Map<String, Object?> data) _call;

  /// 이 기기([token])로 테스트 알림을 [delaySeconds] 뒤에 보낸다 (Functions의 sendTestNotice).
  /// 결과는 users/{uid}.pushTest에도 남아서, 앱이 백그라운드에 있어 응답을 못 받아도 볼 수 있다.
  Future<void> sendTest(String token, {int delaySeconds = 5}) =>
      _call('sendTestNotice', {'token': token, 'delaySeconds': delaySeconds});

  /// 누가 누구에게 얼마 보낼지 함께 보내서, 받는 사람마다 자기 몫을 알려준다.
  Future<void> settleRequest(String tripId, List<Transfer> transfers) {
    if (transfers.isEmpty) return Future.value();
    return _send({
      'tripId': tripId,
      'type': 'settleRequest',
      'transfers': [
        for (final t in transfers)
          {'from': t.from.id, 'to': t.to.id, 'amount': t.amount},
      ],
    });
  }

  Future<void> settled(String tripId, int count) =>
      _send({'tripId': tripId, 'type': 'settled', 'count': count});

  Future<void> _send(Map<String, Object?> data) async {
    try {
      await _call('sendTripNotice', data);
    } catch (e) {
      debugPrint('Trip notice failed: $e');
    }
  }
}
