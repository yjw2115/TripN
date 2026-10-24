import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/expense/data/expense_repository.dart';
import 'features/expense/domain/expense.dart';
import 'features/receipt/data/gemini_receipt_parser.dart';
import 'features/receipt/data/receipt_image_service.dart';
import 'features/receipt/data/receipt_parser.dart';
import 'features/trip/data/trip_repository.dart';
import 'features/trip/domain/trip.dart';

final receiptParserProvider =
    Provider<ReceiptParser>((ref) => GeminiReceiptParser());

final receiptImageServiceProvider =
    Provider<ReceiptImageService>((ref) => ReceiptImageService());

final expenseRepositoryProvider = Provider<ExpenseRepository>(
    (ref) => ExpenseRepository(FirebaseFirestore.instance));

final tripRepositoryProvider = Provider<TripRepository>(
    (ref) => TripRepository(FirebaseFirestore.instance));

/// 1단계는 익명 로그인으로 시작한다. 나중에 소셜 로그인을 붙이면 계정 연결로 이어진다.
final currentUserProvider = FutureProvider<User>((ref) async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser;
  if (user != null) return user;
  final credential = await auth.signInAnonymously();
  return credential.user!;
});

/// 내가 들어가 있는 여행. 처음 열면 기본 여행을 하나 만들어 둔다.
final myTripsProvider = StreamProvider<List<Trip>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  final repo = ref.watch(tripRepositoryProvider);
  await repo.ensureTrip(user.uid);
  yield* repo.watchTrips(user.uid);
});

final selectedTripIdProvider = StreamProvider<String?>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  yield* ref.watch(tripRepositoryProvider).watchSelectedTripId(user.uid);
});

/// 고른 여행. 고른 적이 없거나 그 여행에서 나갔으면 가장 최근 여행.
final currentTripProvider = FutureProvider<Trip>((ref) async {
  final trips = await ref.watch(myTripsProvider.future);
  final selectedId = await ref.watch(selectedTripIdProvider.future);
  final trip = trips.firstWhereOrNull((t) => t.id == selectedId) ?? trips.firstOrNull;
  if (trip == null) throw StateError('No trip to show');
  return trip;
});

/// 아직 참여하기 전인 여행(초대 화면)에서도 쓸 수 있게 여행 id로 받는다.
final tripMembersProvider = StreamProvider.autoDispose
    .family<List<Member>, String>((ref, tripId) =>
        ref.watch(tripRepositoryProvider).watchMembers(tripId));

final membersProvider = StreamProvider<List<Member>>((ref) async* {
  final tripId = await ref.watch(currentTripProvider.selectAsync((t) => t.id));
  yield* ref.watch(tripRepositoryProvider).watchMembers(tripId);
});

/// 지금 여행에서 나에게 연결된 멤버.
final myMemberProvider = FutureProvider<Member?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final members = await ref.watch(membersProvider.future);
  return members.firstWhereOrNull((m) => m.uid == user.uid);
});

final expensesProvider = StreamProvider<List<Expense>>((ref) async* {
  final tripId = await ref.watch(currentTripProvider.selectAsync((t) => t.id));
  yield* ref.watch(expenseRepositoryProvider).watchExpenses(tripId);
});
