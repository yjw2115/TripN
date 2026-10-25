import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/features/trip/data/trip_repository.dart';
import 'package:travelen/features/trip/domain/bank.dart';
import 'package:travelen/features/trip/domain/trip.dart';
import 'package:travelen/features/trip/presentation/widgets/account_sheet.dart';

/// 버튼을 누르면 [member]의 계좌 시트를 연다.
Widget _app(TripRepository repository, Member member) => ProviderScope(
      overrides: [tripRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => editAccount(context, ref, 't', member),
                child: const Text('계좌 열기'),
              ),
            ),
          ),
        ),
      ),
    );

Future<FakeFirebaseFirestore> _db(Member member) async {
  final db = FakeFirebaseFirestore();
  await db.doc('trips/t/members/${member.id}').set({'name': member.name});
  return db;
}

void main() {
  group('Bank', () {
    test('every icon is bundled', () {
      for (final bank in Bank.all) {
        final asset = bank.asset;
        if (asset != null) {
          expect(File(asset).existsSync(), isTrue, reason: asset);
        }
      }
    });

    test('no two banks answer to the same name', () {
      for (final bank in Bank.all) {
        for (final name in [bank.label, bank.name, ...bank.aliases]) {
          expect(Bank.find(name), same(bank), reason: name);
        }
      }
    });

    test('recognizes bank names typed before the list existed', () {
      expect(Bank.find('국민은행')?.name, 'KB국민은행');
      expect(Bank.find('kb 국민')?.name, 'KB국민은행');
      expect(Bank.find(' 카카오뱅크 ')?.name, '카카오뱅크');
      expect(Bank.find('대구은행')?.name, 'iM뱅크');
      expect(Bank.find('NH농협')?.name, 'NH농협은행');
      expect(Bank.find('토스증권'), isNull);
      expect(Bank.find(''), isNull);
    });
  });

  group('account sheet', () {
    const minsu = Member(id: 'm', name: '민수');

    testWidgets('picks the bank from the icon grid', (tester) async {
      final db = await _db(minsu);
      await tester.pumpWidget(_app(TripRepository(db), minsu));
      await tester.tap(find.text('계좌 열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('은행 선택'));
      await tester.pumpAndSettle();
      expect(find.text('어느 은행 계좌인가요?'), findsOneWidget);
      expect(find.text('국민'), findsOneWidget);
      await tester.tap(find.text('카카오뱅크'));
      await tester.pumpAndSettle();

      expect(find.text('카카오뱅크'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '3333-01-1234567');
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      final account = (await db.doc('trips/t/members/m').get()).data()!['account'];
      expect(account, {
        'bank': '카카오뱅크',
        'number': '3333-01-1234567',
        'holder': '민수',
      });
    });

    testWidgets('a bank typed before shows with its icon', (tester) async {
      const typed = Member(
        id: 'm',
        name: '민수',
        account: BankAccount(bank: '국민은행', number: '123', holder: '민수'),
      );
      await tester.pumpWidget(_app(TripRepository(await _db(typed)), typed));
      await tester.tap(find.text('계좌 열기'));
      await tester.pumpAndSettle();

      expect(find.text('KB국민은행'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a bank that is not listed can be typed in', (tester) async {
      final db = await _db(minsu);
      await tester.pumpWidget(_app(TripRepository(db), minsu));
      await tester.tap(find.text('계좌 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('은행 선택'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('직접 입력'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('직접 입력'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '토스증권');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text('토스증권'), findsOneWidget);
      expect(find.text('토'), findsOneWidget); // 아이콘 대신 첫 글자
    });
  });
}
