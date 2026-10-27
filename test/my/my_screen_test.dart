import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelen/app_providers.dart';
import 'package:travelen/features/my/presentation/my_screen.dart';
import 'package:travelen/features/trip/domain/trip.dart';

void main() {
  testWidgets('shows the version and build number at the bottom',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        profileProvider.overrideWith((ref) => Stream.value(const Profile())),
        myMemberProvider.overrideWith((ref) async => null),
        appVersionProvider.overrideWith((ref) async => '1.0.0+11'),
      ],
      child: const MaterialApp(home: MyScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1.0.0+11'), findsOneWidget);
    expect(find.text('오픈소스 라이선스'), findsNothing);
    // 화면 맨 아래, 알림 줄보다 한참 아래에 있다.
    final version = tester.getBottomLeft(find.text('1.0.0+11')).dy;
    expect(version, greaterThan(tester.getBottomLeft(find.text('알림')).dy + 200));
  });
}
