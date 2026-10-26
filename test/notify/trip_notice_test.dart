import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/features/notify/data/trip_notice_sender.dart';
import 'package:travelen/features/notify/domain/trip_notice.dart';
import 'package:travelen/features/settlement/domain/settlement.dart';
import 'package:travelen/features/trip/domain/trip.dart';

void main() {
  group('TripNotice', () {
    test('reads what Functions put in the message data', () {
      final notice = TripNotice.fromData({'tripId': 't1', 'type': 'settleRequest'},
          title: '도쿄', body: '지민님이 정산을 요청했어요');
      expect(notice?.tripId, 't1');
      expect(notice?.type, NoticeType.settleRequest);
      expect(notice?.opensSettlement, isTrue);
      expect(TripNotice.fromData({'tripId': 't1', 'type': 'expense'})!.opensSettlement,
          isFalse);
    });

    test('a test notice belongs to no trip and opens nothing', () {
      final notice = TripNotice.fromData({'type': 'test'}, body: '테스트');
      expect(notice?.type, NoticeType.test);
      expect(notice?.tripId, '');
      expect(notice?.opensSettlement, isFalse);
    });

    test('ignores messages that are not about a trip', () {
      expect(TripNotice.fromData({}), isNull);
      expect(TripNotice.fromData({'tripId': 't1', 'type': 'promo'}), isNull);
      expect(TripNotice.fromData({'type': 'expense'}), isNull);
    });
  });

  group('TripNoticeSender', () {
    late List<Map<String, Object?>> sent;
    late List<String> calls;
    late TripNoticeSender sender;

    setUp(() {
      sent = [];
      calls = [];
      sender = TripNoticeSender((name, data) async {
        calls.add(name);
        sent.add(data);
      });
    });

    test('a settlement request carries who sends whom how much, by member id',
        () async {
      const jimin = Member(id: 'j', name: '지민');
      const minsu = Member(id: 'm', name: '민수');
      await sender.settleRequest(
          't1', [const Transfer(from: minsu, to: jimin, amount: 23069)]);
      expect(sent.single, {
        'tripId': 't1',
        'type': 'settleRequest',
        'transfers': [
          {'from': 'm', 'to': 'j', 'amount': 23069},
        ],
      });
    });

    test('a test notice goes to this device only, after a delay', () async {
      await sender.sendTest('my-token');
      expect(calls, ['sendTestNotice']);
      expect(sent.single, {'token': 'my-token', 'delaySeconds': 5});
    });

    test('nothing to send, nothing sent', () async {
      await sender.settleRequest('t1', const []);
      expect(sent, isEmpty);
    });

    test('a failed notice never reaches the screen', () async {
      final failing =
          TripNoticeSender((_, _) async => throw Exception('offline'));
      await expectLater(failing.settled('t1', 3), completes);
    });
  });
}
