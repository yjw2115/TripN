import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/trip/data/trip_repository.dart';
import 'package:travelen/features/trip/domain/trip.dart';

// 보안 규칙은 tool/firestore_rules에서 에뮬레이터로 따로 확인한다.
void main() {
  late FakeFirebaseFirestore db;
  late TripRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = TripRepository(db, random: Random(1));
  });

  Future<Map<String, dynamic>> data(String path) async =>
      (await db.doc(path).get()).data()!;

  group('ensureTrip', () {
    test('creates one default trip with me as its first member', () async {
      await repo.ensureTrip('alice');
      await repo.ensureTrip('alice');

      final trips = await repo.watchTrips('alice').first;
      expect(trips, hasLength(1));
      expect(trips.single.name, '내 여행');
      expect(trips.single.memberUids, ['alice']);

      final members = await repo.watchMembers(trips.single.id).first;
      expect(members.single.id, 'alice');
      expect(members.single.uid, 'alice');
      expect(members.single.name, defaultMyName);
      expect(await repo.watchSelectedTripId('alice').first, trips.single.id);
    });

    test('moves a 1.0.0+3 trip to the new structure instead of creating one',
        () async {
      await db.doc('trips/old').set(
          {'name': '내 여행', 'ownerId': 'alice', 'memberIds': ['alice']});

      await repo.ensureTrip('alice');

      final trip = await data('trips/old');
      expect(trip['memberUids'], ['alice']);
      expect(trip.containsKey('memberIds'), isFalse);
      // 옛 지출의 payerId(uid)가 그대로 멤버 id가 된다.
      expect((await data('trips/old/members/alice'))['uid'], 'alice');
      expect(await repo.watchTrips('alice').first, hasLength(1));
    });
  });

  group('profile', () {
    const account =
        BankAccount(bank: '카카오뱅크', number: '3333-01-1234567', holder: '지민');

    test('keeps my name and account next to the selected trip', () async {
      await repo.selectTrip('alice', 't1');
      await repo.setProfileName('alice', '지민');
      await repo.setProfileAccount('alice', account);

      final profile = await repo.watchProfile('alice').first;
      expect(profile.name, '지민');
      expect(profile.account?.display, '카카오뱅크 3333-01-1234567 지민');
      expect(await repo.watchSelectedTripId('alice').first, 't1');

      await repo.setProfileAccount('alice', null);
      expect((await repo.watchProfile('alice').first).account, isNull);
    });

    test('notifications start on, can be turned off per topic, and keep each device',
        () async {
      expect((await repo.watchProfile('alice').first).notifyExpense, isTrue);

      await repo.setNotify('alice', NotifyTopic.expense, false);
      await repo.addPushToken('alice', 'phone');
      await repo.addPushToken('alice', 'phone');
      await repo.addPushToken('alice', 'tablet');

      final profile = await repo.watchProfile('alice').first;
      expect(profile.notifyExpense, isFalse);
      expect(profile.notifySettlement, isTrue);
      expect((await data('users/alice'))['fcmTokens'], ['phone', 'tablet']);
    });

    test('a new trip starts with my account when one is given', () async {
      final tripId = await repo.createTrip(
          uid: 'alice', name: '도쿄', myName: '지민', myAccount: account);

      final me = (await repo.watchMembers(tripId).first).single;
      expect(me.account?.number, '3333-01-1234567');
    });
  });

  group('members', () {
    late String tripId;

    setUp(() async {
      tripId = await repo.createTrip(uid: 'alice', name: '도쿄', myName: '지민');
    });

    test('name-only companions are listed after me, in the order added',
        () async {
      await repo.addGuest(tripId: tripId, name: '민수', uid: 'alice');
      await repo.addGuest(tripId: tripId, name: '서연', uid: 'alice');

      final members = await repo.watchMembers(tripId).first;
      expect(members.map((m) => m.name), ['지민', '민수', '서연']);
      expect(members.skip(1).every((m) => m.isGuest), isTrue);
    });

    test('an invite code is created once and the trip name follows renames',
        () async {
      final code = await repo.ensureInviteCode(tripId, 'alice');
      expect(await repo.ensureInviteCode(tripId, 'alice'), code);
      expect(normalizeInviteCode(code), code);

      final trip = (await repo.watchTrips('alice').first).single;
      expect(trip.inviteCode, code);
      await repo.renameTrip(trip, '오사카');

      final invite = await repo.findInvite(code);
      expect(invite?.tripId, tripId);
      expect(invite?.tripName, '오사카');
      expect(await repo.findInvite('ZZZZZZ'), isNull);
    });

    test('a joiner claims a name-only companion and keeps their records',
        () async {
      await repo.addGuest(tripId: tripId, name: '민수', uid: 'alice');
      final guest = (await repo.watchMembers(tripId).first).last;
      final invite =
          (await repo.findInvite(await repo.ensureInviteCode(tripId, 'alice')))!;

      await repo.join(invite, 'bob');
      expect((await data('trips/$tripId/members/bob'))['joinCode'], invite.code);
      expect(await repo.watchSelectedTripId('bob').first, tripId);

      await repo.claimGuest(tripId: tripId, guestId: guest.id, uid: 'bob');
      final members = await repo.watchMembers(tripId).first;
      expect(members.map((m) => (m.name, m.uid)),
          [('지민', 'alice'), ('민수', 'bob')]);
      expect((await repo.watchTrips('bob').first).single.id, tripId);
    });

    test('leaving keeps me as a name-only companion', () async {
      final invite =
          (await repo.findInvite(await repo.ensureInviteCode(tripId, 'alice')))!;
      await repo.join(invite, 'bob');
      await repo.renameMember(tripId, 'bob', '밥');

      await repo.leaveTrip(tripId: tripId, memberId: 'bob', uid: 'bob');

      expect(await repo.watchTrips('bob').first, isEmpty);
      final bob = (await repo.watchMembers(tripId).first).last;
      expect((bob.name, bob.isGuest), ('밥', true));
    });

    test('deleting a trip removes its members, expenses and invite', () async {
      final code = await repo.ensureInviteCode(tripId, 'alice');
      for (var i = 0; i < 10; i++) {
        await repo.addGuest(tripId: tripId, name: '동행$i', uid: 'alice');
        await db.collection('trips/$tripId/expenses').add({'payerId': 'alice'});
      }
      final trip = (await repo.watchTrips('alice').first).single;

      await repo.deleteTrip(trip);

      expect((await db.collection('trips/$tripId/members').get()).docs, isEmpty);
      expect((await db.collection('trips/$tripId/expenses').get()).docs, isEmpty);
      expect((await db.doc('invites/$code').get()).exists, isFalse);
      expect((await db.doc('trips/$tripId').get()).exists, isFalse);
    });
  });

  group('invite codes', () {
    test('generated codes avoid look-alike characters', () {
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final code = generateInviteCode(random);
        expect(code, hasLength(inviteCodeLength));
        expect(code, isNot(matches(RegExp('[01ILO]'))));
      }
    });

    test('typed codes are cleaned up, and malformed ones rejected', () {
      expect(normalizeInviteCode(' k7q-2mx '), 'K7Q2MX');
      expect(normalizeInviteCode('K7Q 2MX'), 'K7Q2MX');
      expect(normalizeInviteCode('K7Q2M'), isNull);
      expect(normalizeInviteCode('K7Q2M0'), isNull);
    });

    test('the invite message carries the link, and the code on its own line',
        () {
      final lines = inviteMessage('도쿄', 'K7Q2MX').split('\n');
      expect(lines, contains('https://travelen-468bc.web.app/join/K7Q2MX'));
      expect(lines.last, 'K7Q2MX');
    });
  });

  test('an expense involves its payer, item participants and takers', () {
    final expense = Expense(
      id: 'e1',
      title: '라멘',
      category: ExpenseCategory.food,
      currency: Currency.of('JPY'),
      totalMinor: 2000,
      paidAt: DateTime(2026, 10, 1),
      payerId: 'alice',
      createdBy: 'alice',
      receipt: Receipt(
        merchantName: '라멘집',
        currency: Currency.of('JPY'),
        items: const [
          ReceiptItem(
              id: 'i1', name: '라멘', amountMinor: 2000, participantIds: ['g1']),
          ReceiptItem(
              id: 'i2',
              name: '교자',
              quantity: 2,
              amountMinor: 800,
              takenBy: {'g3': 1}),
        ],
        totalMinor: 2800,
      ),
    );
    expect(expense.involves('alice'), isTrue);
    expect(expense.involves('g1'), isTrue);
    expect(expense.involves('g3'), isTrue); // 교자를 가져갔다
    expect(expense.involves('g2'), isFalse);
  });
}
