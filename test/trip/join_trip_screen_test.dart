import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/features/trip/data/trip_repository.dart';
import 'package:travelen/features/trip/presentation/join_trip_screen.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFirebaseFirestore db;
  late TripRepository repo;
  late String tripId;
  late String code;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = TripRepository(db);
    tripId = await repo.createTrip(uid: 'alice', name: '도쿄 여행', myName: '지민');
    await repo.addGuest(tripId: tripId, name: '민수', uid: 'alice');
    code = await repo.ensureInviteCode(tripId, 'alice');
  });

  Widget app({String initialLocation = '/join'}) => ProviderScope(
        overrides: [
          tripRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) async => _FakeUser('bob')),
          myTripsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: initialLocation, routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('홈')),
            GoRoute(path: '/join', builder: (_, _) => const JoinTripScreen()),
            GoRoute(
              path: '/join/:code',
              builder: (_, state) =>
                  JoinTripScreen(initialCode: state.pathParameters['code']),
            ),
          ]),
        ),
      );

  Future<void> enterCode(WidgetTester tester, String text) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
  }

  testWidgets('joins with a code and claims the name-only companion',
      (tester) async {
    await enterCode(tester, code.toLowerCase());
    expect(find.text('도쿄 여행'), findsOneWidget);

    await tester.tap(find.text('참여하기'));
    await tester.pumpAndSettle();
    expect(find.text('이 여행에서 누구세요?'), findsOneWidget);

    await tester.tap(find.text('민수'));
    await tester.pump();
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    final members = await repo.watchMembers(tripId).first;
    expect(members.map((m) => (m.name, m.uid)),
        [('지민', 'alice'), ('민수', 'bob')]);
  });

  testWidgets('someone not on the list joins under a new name', (tester) async {
    await enterCode(tester, code);
    await tester.tap(find.text('참여하기'));
    await tester.pumpAndSettle();
    // 동행자 목록이 있으면 아무것도 고르지 않은 채로 시작한다.
    expect(find.byType(TextField), findsNothing);
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('목록에 없어요'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '서연');
    await tester.pump();
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    final members = await repo.watchMembers(tripId).first;
    expect(members.map((m) => (m.name, m.uid)),
        [('지민', 'alice'), ('민수', null), ('서연', 'bob')]);
  });

  testWidgets('an invite link skips typing the code', (tester) async {
    await tester.pumpWidget(
        app(initialLocation: '/join/${code.toLowerCase()}'));
    await tester.pumpAndSettle();

    expect(find.text('이 여행에 참여할까요?'), findsOneWidget);
    expect(find.text('도쿄 여행'), findsOneWidget);
    // 링크로 바로 열려 돌아갈 화면이 없으니 닫기 버튼으로 홈에 간다.
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('an unknown code shows an error and stays on the code step',
      (tester) async {
    await enterCode(tester, 'ZZZZZZ');

    expect(find.text('코드를 찾지 못했어요. 다시 확인해 주세요.'), findsOneWidget);
    expect(find.text('다음'), findsOneWidget);
  });
}
