import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/core/money/currency.dart';
import 'package:travelen/features/expense/domain/expense.dart';
import 'package:travelen/features/receipt/domain/receipt.dart';
import 'package:travelen/features/settlement/presentation/bet_game_screen.dart';
import 'package:travelen/features/settlement/presentation/bet_setup_screen.dart';
import 'package:travelen/features/settlement/presentation/games/ddakji_game.dart';
import 'package:travelen/features/settlement/presentation/games/roulette_game.dart';
import 'package:travelen/features/settlement/presentation/games/wave_race_game.dart';
import 'package:travelen/features/trip/data/trip_repository.dart';
import 'package:travelen/features/trip/domain/trip.dart';

const _jimin = Member(id: 'j', name: '지민', uid: 'u1');
const _minsu = Member(id: 'm', name: '민수');
const _seoyeon = Member(id: 's', name: '서연');
const _members = [_jimin, _minsu, _seoyeon];

Expense _expense(String id, String title, String payer, int total) => Expense(
  id: id,
  title: title,
  category: ExpenseCategory.food,
  currency: Currency.krw,
  totalMinor: total,
  paidAt: DateTime(2026, 10, 23),
  payerId: payer,
  createdBy: 'u1',
  participantIds: const ['j', 'm', 's'],
);

Widget _host(Widget game) => MaterialApp(home: Scaffold(body: game));

void main() {
  testWidgets('whoever flips the red ddakji loses', (tester) async {
    Member? loser;
    await tester.pumpWidget(
      _host(
        DdakjiGame(
          players: _members,
          random: Random(3),
          onLoser: (m) => loser = m,
        ),
      ),
    );
    await tester.pump();

    // 첫 접시를 집기 전에는 접시 수를 바꿀 수 있다.
    await tester.tap(find.text('9'));
    await tester.pump();
    expect(find.byKey(const ValueKey('ddakji-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('ddakji-9')), findsNothing);

    String? turn;
    for (var i = 0; i < 9 && loser == null; i++) {
      turn = tester.widget<Text>(find.textContaining('님 차례')).data;
      await tester.tap(find.byKey(ValueKey('ddakji-$i')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 800));
      if (i == 0) expect(find.text('9'), findsNothing);
    }
    expect(loser, isNotNull);
    expect(turn, '${loser!.name}님 차례');
    expect(find.text('${loser!.name}님 빨간 딱지!'), findsOneWidget);
  });

  testWidgets('the last fish to arrive loses', (tester) async {
    List<Member>? ranking;
    await tester.pumpWidget(
      _host(
        WaveRaceGame(
          players: _members,
          random: Random(5),
          onFinish: (r) => ranking = r,
        ),
      ),
    );

    // 장애물은 미리 보이지 않고 부딪히기 직전에 나타난다.
    for (final hazard in ['🪝', '🦈']) {
      expect(find.text(hazard), findsNothing);
    }
    await tester.tap(find.text('출발!'));
    var ticks = 0, bumped = false, warned = false;
    for (; ticks < 300 && ranking == null; ticks++) {
      await tester.pump(const Duration(milliseconds: 100));
      bumped |= find.text('💫').evaluate().isNotEmpty;
      warned |= find.text('❗').evaluate().isNotEmpty;
    }
    expect(ranking, isNotNull);
    expect(ranking!.toSet(), _members.toSet());
    expect(find.text('도착!'), findsOneWidget);
    // 장애물에 부딪혀 밀려나고, 카운트다운까지 10초 넘게 헤엄친다.
    expect(bumped, isTrue);
    expect(warned, isTrue);
    expect(ticks, greaterThan(100));
  });

  group('roulette', () {
    test('stops inside the chosen slice after the given spins', () {
      final random = Random(11);
      for (var i = 0; i < 2000; i++) {
        final count = 2 + random.nextInt(11);
        final index = random.nextInt(count);
        final from = (random.nextDouble() - 0.5) * 40;
        final stop = rouletteStop(
          from: from,
          index: index,
          count: count,
          spins: 5,
          within: 0.15 + random.nextDouble() * 0.7,
        );
        expect(rouletteSegmentAt(stop, count), index);
        expect(stop - from, inInclusiveRange(5 * 2 * pi, 6 * 2 * pi));
      }
    });

    test('neighbouring slices never share a colour, even across the top', () {
      for (var count = 2; count <= 24; count++) {
        for (var i = 0; i < count; i++) {
          expect(rouletteColor(i, count), isNot(rouletteColor((i + 1) % count, count)),
              reason: '$count slices, $i and ${(i + 1) % count}');
        }
      }
    });

    testWidgets('the needle picks who loses', (tester) async {
      Member? loser;
      await tester.pumpWidget(
        _host(
          RouletteGame(
            players: _members,
            random: Random(7),
            onLoser: (m) => loser = m,
          ),
        ),
      );
      expect(find.text('누가 걸릴까요?'), findsOneWidget);

      await tester.tap(find.text('돌리기!'));
      await tester.pump();
      expect(find.text('두구두구…'), findsOneWidget);
      for (var i = 0; i < 80 && loser == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(loser, isNotNull);
      expect(find.text('${loser!.name}님!'), findsOneWidget);
    });
  });

  testWidgets('pick a treat, ride the waves, and the result goes into the trip', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('trips/t').set({
      'name': '도쿄 여행',
      'ownerId': 'u1',
      'memberUids': ['u1'],
    });
    bool? applied;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  applied = await context.push<bool>('/settlement/bet'),
              child: const Text('열기'),
            ),
          ),
        ),
        GoRoute(
          path: '/settlement/bet',
          builder: (context, state) => const BetSetupScreen(),
        ),
        GoRoute(
          path: '/settlement/bet/play',
          builder: (context, state) => BetGameScreen(
            args: state.extra! as BetPlayArgs,
            random: Random(5),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTripProvider.overrideWith(
            (ref) async => const Trip(
              id: 't',
              name: '도쿄 여행',
              ownerId: 'u1',
              memberUids: ['u1'],
            ),
          ),
          membersProvider.overrideWith((ref) => Stream.value(_members)),
          expensesProvider.overrideWith(
            (ref) => Stream.value([
              _expense('dinner', '저녁', 'j', 90000),
              _expense('sushi', '스시로', 'm', 30000),
            ]),
          ),
          tripRepositoryProvider.overrideWithValue(TripRepository(db)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('한 턱 쏘기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('스시로'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('파도타기'), 200);
    await tester.ensureVisible(find.text('파도타기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('파도타기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('게임 시작'));
    // 파도는 계속 출렁여서 화면이 멈추지 않는다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('출발!'));
    for (var i = 0; i < 300 && find.text('정산에 반영하기').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 3));
    final loser = _members.firstWhere(
      (m) => find.text('${m.name}님 당첨!').evaluate().isNotEmpty,
    );
    // 스시로 30,000원은 셋이 10,000원씩. 걸린 사람은 다른 두 사람 몫을 낸다.
    expect(find.textContaining('다른 사람 몫 20,000원을 대신 내요'), findsOneWidget);

    await tester.tap(find.text('정산에 반영하기'));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
    final bet = (await db.doc('trips/t').get()).data()!['settlementBet'];
    expect(bet, {
      'game': 'wave',
      'stake': 'treat',
      'expenseId': 'sushi',
      'loserId': loser.id,
      'participantIds': ['j', 'm', 's'],
    });
  });
}
