import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import '../domain/trip.dart';

/// 초대 코드로 찾은 여행. 참여하기 전이라 이름만 보인다.
class InviteInfo {
  const InviteInfo({required this.code, required this.tripId, required this.tripName});

  final String code;
  final String tripId;
  final String tripName;
}

/// Firestore 구조
///   users/{uid}                         currentTripId
///   trips/{tripId}                      name, ownerId, memberUids, inviteCode, manualRates, createdAt
///   trips/{tripId}/members/{memberId}   name, uid(이름만 있는 동행자는 null), createdBy, createdAt
///   invites/{code}                      tripId, tripName, createdBy, createdAt
///
/// 앱 사용자가 스스로 만든 멤버(여행을 만들거나 초대로 들어온 사람)는 문서 id가 uid다.
/// 이름으로 추가한 동행자는 자동 id이고, 본인이 들어와 고르면 uid만 채운다.
class TripRepository {
  TripRepository(this._db, {Random? random})
      : _random = random ?? Random.secure();

  final FirebaseFirestore _db;
  final Random _random;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection('trips');

  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('invites');

  CollectionReference<Map<String, dynamic>> _members(String tripId) =>
      _trips.doc(tripId).collection('members');

  Map<String, Object?> _memberData(
          {required String name, required String? uid, required String createdBy}) =>
      {
        'name': name,
        'uid': uid,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// 여행이 하나도 없으면 기본 여행을 만든다.
  Future<void> ensureTrip(String uid) async {
    final mine =
        await _trips.where('memberUids', arrayContains: uid).limit(1).get();
    if (mine.docs.isNotEmpty) return;
    if (await _migrateLegacyTrips(uid)) return;
    await createTrip(uid: uid, name: '내 여행', myName: defaultMyName);
  }

  /// 1.0.0+3까지는 여행마다 memberIds(uid 목록)만 있고 멤버 문서가 없었다.
  /// 그때 지출의 payerId는 uid라서, 내 멤버 문서 id를 uid로 만들면 그대로 이어진다.
  Future<bool> _migrateLegacyTrips(String uid) async {
    final legacy = (await _trips.where('memberIds', arrayContains: uid).get())
        .docs
        .where((d) => d.data()['ownerId'] == uid)
        .toList();
    if (legacy.isEmpty) return false;
    final batch = _db.batch();
    for (final doc in legacy) {
      batch
        ..update(doc.reference, {
          'memberUids': [uid],
          'memberIds': FieldValue.delete(),
        })
        ..set(_members(doc.id).doc(uid),
            _memberData(name: defaultMyName, uid: uid, createdBy: uid));
    }
    await batch.commit();
    return true;
  }

  /// 새 여행을 만들고 바로 고른다.
  Future<String> createTrip({
    required String uid,
    required String name,
    required String myName,
  }) async {
    final ref = _trips.doc();
    final batch = _db.batch()
      ..set(ref, {
        'name': name,
        'ownerId': uid,
        'memberUids': [uid],
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(_members(ref.id).doc(uid),
          _memberData(name: myName, uid: uid, createdBy: uid))
      ..set(_users.doc(uid), {'currentTripId': ref.id}, SetOptions(merge: true));
    await batch.commit();
    return ref.id;
  }

  /// 내가 들어가 있는 여행. 최근에 만든 것부터.
  Stream<List<Trip>> watchTrips(String uid) => _trips
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs
          .sorted((a, b) => _compareCreatedAt(b.data(), a.data()))
          .map((d) => Trip.fromMap(d.id, d.data()))
          .toList());

  Stream<String?> watchSelectedTripId(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((s) => s.data()?['currentTripId'] as String?);

  Future<void> selectTrip(String uid, String tripId) => _users
      .doc(uid)
      .set({'currentTripId': tripId}, SetOptions(merge: true));

  /// 초대 문서에도 여행 이름이 있어서 같이 바꾼다.
  Future<void> renameTrip(Trip trip, String name) {
    final batch = _db.batch()..update(_trips.doc(trip.id), {'name': name});
    final code = trip.inviteCode;
    if (code != null) batch.update(_invites.doc(code), {'tripName': name});
    return batch.commit();
  }

  /// 동행자 모두 같은 값을 쓰도록 여행에 둔다.
  Future<void> setManualRate(String tripId, String currencyCode, double krwPerUnit) =>
      _trips.doc(tripId).update({'manualRates.$currencyCode': krwPerUnit});

  /// 먼저 들어온 사람부터.
  Stream<List<Member>> watchMembers(String tripId) =>
      _members(tripId).snapshots().map((s) => s.docs
          .sorted((a, b) => _compareCreatedAt(a.data(), b.data()))
          .map((d) => Member.fromMap(d.id, d.data()))
          .toList());

  Future<void> addGuest(
          {required String tripId, required String name, required String uid}) =>
      _members(tripId).add(_memberData(name: name, uid: null, createdBy: uid));

  Future<void> renameMember(String tripId, String memberId, String name) =>
      _members(tripId).doc(memberId).update({'name': name});

  Future<void> deleteMember(String tripId, String memberId) =>
      _members(tripId).doc(memberId).delete();

  /// 여행의 초대 코드. 없으면 겹치지 않는 코드를 새로 만든다.
  Future<String> ensureInviteCode(String tripId, String uid) async {
    final tripRef = _trips.doc(tripId);
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = generateInviteCode(_random);
      final inviteRef = _invites.doc(code);
      final result = await _db.runTransaction<String?>((tx) async {
        final trip = await tx.get(tripRef);
        final existing = trip.data()?['inviteCode'] as String?;
        if (existing != null) return existing;
        if ((await tx.get(inviteRef)).exists) return null;
        tx
          ..set(inviteRef, {
            'tripId': tripId,
            'tripName': trip.data()?['name'] ?? '',
            'createdBy': uid,
            'createdAt': FieldValue.serverTimestamp(),
          })
          ..update(tripRef, {'inviteCode': code});
        return code;
      });
      if (result != null) return result;
    }
    throw StateError('Could not allocate an invite code');
  }

  /// 오프라인 캐시에서 "없음"으로 오인하지 않게 서버에서 읽는다.
  Future<InviteInfo?> findInvite(String code) async {
    final snap =
        await _invites.doc(code).get(const GetOptions(source: Source.server));
    final data = snap.data();
    if (data == null) return null;
    return InviteInfo(
      code: code,
      tripId: data['tripId'] as String,
      tripName: data['tripName'] as String? ?? '',
    );
  }

  /// 초대 코드로 들어간다. 일단 [joiningMemberName]으로 내 멤버를 만들고,
  /// 들어간 뒤에 [claimGuest]나 [renameMember]로 누구인지 정한다.
  /// 보안 규칙은 내 멤버 문서의 joinCode가 여행의 초대 코드와 같은지 본다.
  Future<void> join(InviteInfo invite, String uid) {
    final batch = _db.batch()
      ..set(_members(invite.tripId).doc(uid), {
        ..._memberData(name: joiningMemberName, uid: uid, createdBy: uid),
        'joinCode': invite.code,
      })
      ..update(_trips.doc(invite.tripId), {
        'memberUids': FieldValue.arrayUnion([uid]),
      })
      ..set(_users.doc(uid), {'currentTripId': invite.tripId},
          SetOptions(merge: true));
    return batch.commit();
  }

  /// 이름만 있던 동행자를 나로 연결하고, 참여할 때 만든 내 멤버는 지운다.
  Future<void> claimGuest(
      {required String tripId, required String guestId, required String uid}) {
    final batch = _db.batch()
      ..update(_members(tripId).doc(guestId), {'uid': uid})
      ..delete(_members(tripId).doc(uid));
    return batch.commit();
  }

  /// 내 멤버는 이름만 있는 동행자로 남겨서 지출 기록과 정산이 깨지지 않게 한다.
  Future<void> leaveTrip(
      {required String tripId, required String memberId, required String uid}) {
    final batch = _db.batch()
      ..update(_members(tripId).doc(memberId), {'uid': null})
      ..update(_trips.doc(tripId), {
        'memberUids': FieldValue.arrayRemove([uid]),
      });
    return batch.commit();
  }

  /// 하위 문서를 먼저 지우고 여행을 지운다 (소유자만).
  /// 보안 규칙이 문서마다 여행 문서를 읽어서, 한 번에 읽을 수 있는 문서 수(20)를 넘지 않게 나눈다.
  Future<void> deleteTrip(Trip trip) async {
    final ref = _trips.doc(trip.id);
    final expenses = await ref.collection('expenses').get();
    final members = await _members(trip.id).get();
    final code = trip.inviteCode;
    final docs = [
      ...expenses.docs.map((d) => d.reference),
      ...members.docs.map((d) => d.reference),
      if (code != null) _invites.doc(code),
    ];
    for (final chunk in docs.slices(8)) {
      final batch = _db.batch();
      for (final doc in chunk) {
        batch.delete(doc);
      }
      await batch.commit();
    }
    await ref.delete();
  }

  /// 서버 시각이 아직 안 정해진(방금 만든) 문서는 가장 최근으로 본다.
  static int _compareCreatedAt(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['createdAt'] as Timestamp?;
    final tb = b['createdAt'] as Timestamp?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  }
}
