import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/expense/data/expense_repository.dart';
import 'features/expense/domain/expense.dart';
import 'features/receipt/data/gemini_receipt_parser.dart';
import 'features/receipt/data/receipt_image_service.dart';
import 'features/receipt/data/receipt_parser.dart';

final receiptParserProvider =
    Provider<ReceiptParser>((ref) => GeminiReceiptParser());

final receiptImageServiceProvider =
    Provider<ReceiptImageService>((ref) => ReceiptImageService());

final expenseRepositoryProvider = Provider<ExpenseRepository>(
    (ref) => ExpenseRepository(FirebaseFirestore.instance));

/// 1단계는 익명 로그인으로 시작한다. 나중에 소셜 로그인을 붙이면 계정 연결로 이어진다.
final currentUserProvider = FutureProvider<User>((ref) async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser;
  if (user != null) return user;
  final credential = await auth.signInAnonymously();
  return credential.user!;
});

final currentTripProvider = FutureProvider<Trip>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  return ref.watch(expenseRepositoryProvider).ensureDefaultTrip(user.uid);
});

final expensesProvider = StreamProvider<List<Expense>>((ref) async* {
  final trip = await ref.watch(currentTripProvider.future);
  yield* ref.watch(expenseRepositoryProvider).watchExpenses(trip.id);
});
