import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/money/currency.dart';
import 'core/money/exchange_rate.dart';
import 'features/expense/data/exchange_rate_repository.dart';
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

/// 함수는 Firestore와 같은 서울 리전에 있다.
final exchangeRateRepositoryProvider = Provider<ExchangeRateRepository>((ref) {
  final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('exchangeRates');
  return ExchangeRateRepository(
    FirebaseFirestore.instance,
    (date) async => Map<String, Object?>.from(
        (await callable.call({'date': date})).data as Map),
  );
});

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

/// 확인 화면에서 미리 보여주고 저장할 때 고정할 환율. 키는 (통화 코드, 영수증 날짜 yyyy-MM-dd).
/// null이면 수출입은행에 없는 통화라 여행에서 직접 정해야 한다.
final rateQuoteProvider = FutureProvider.autoDispose
    .family<FixedRate?, (String, String)>((ref, key) async {
  final (code, date) = key;
  final manual = await ref
      .watch(currentTripProvider.selectAsync((t) => t.manualRates[code]));
  return ref.watch(exchangeRateRepositoryProvider).rateFor(
        Currency.of(code),
        DateTime.parse(date),
        manualRates: {code: ?manual},
      );
});

/// 환율 없이 저장된 지출(오프라인으로 저장했거나 1.0.0+3 이전 지출)에 환율을 채운다.
/// 홈 화면이 지켜보는 동안 동작한다. 동행자 여럿이 동시에 채워도 같은 값이라 괜찮다.
final rateBackfillProvider = Provider<void>((ref) {
  final tried = <String>{};

  Future<void> fill(Trip trip, Expense expense) async {
    try {
      final rate = await ref.read(exchangeRateRepositoryProvider).rateFor(
          expense.currency, expense.paidAt,
          manualRates: trip.manualRates);
      if (rate == null) return;
      await ref
          .read(expenseRepositoryProvider)
          .fillRate(trip.id, expense.id, rate);
    } catch (e) {
      debugPrint('Rate backfill failed for ${expense.id}: $e');
    }
  }

  void scan() {
    final trip = ref.read(currentTripProvider).value;
    final expenses = ref.read(expensesProvider);
    // 여행을 바꾸는 중에는 이전 여행의 지출이 남아 있다.
    if (trip == null || expenses.isLoading || !expenses.hasValue) return;
    for (final e in expenses.requireValue) {
      if (e.rate != null) continue;
      // 여행에서 환율을 새로 정하면 다시 시도한다.
      final key = '${trip.id}/${e.id}/${trip.manualRates[e.currency.code]}';
      if (tried.add(key)) unawaited(fill(trip, e));
    }
  }

  ref.listen(expensesProvider, (_, _) => scan());
  ref.listen(currentTripProvider, (_, _) => scan());
  scan();
});
