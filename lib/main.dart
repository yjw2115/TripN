import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'firebase_options.dart';

/// 디버그 빌드에서 쓸 App Check 디버그 토큰.
/// `--dart-define=APP_CHECK_DEBUG_TOKEN=...`으로 고정해 두면 콘솔에 한 번만 등록하면 된다.
/// 비워 두면 SDK가 기기마다 토큰을 만들어 로그에 출력한다.
const _appCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

/// 디버그 빌드에서 `--dart-define=FIRESTORE_EMULATOR=localhost:8080`을 주면 로컬 에뮬레이터를 쓴다.
/// 보안 규칙을 배포하기 전에 앱으로 확인할 때 쓴다.
const _firestoreEmulator = String.fromEnvironment('FIRESTORE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Gemini 호출(Firebase AI Logic)을 앱 밖에서 쓰지 못하게 막는다.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? AndroidDebugProvider(
            debugToken: _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken)
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? AppleDebugProvider(
            debugToken: _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken)
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
  if (kDebugMode && _firestoreEmulator.isNotEmpty) {
    final [host, port] = _firestoreEmulator.split(':');
    FirebaseFirestore.instance.useFirestoreEmulator(host, int.parse(port));
  }
  await initializeDateFormatting('ko');
  runApp(const ProviderScope(retry: _retry, child: TravelenApp()));
}

/// 잠깐 끊긴 네트워크를 위해 3번까지만 다시 시도한다 (기본값은 10번이라 오류가 늦게 보인다).
Duration? _retry(int retryCount, Object error) =>
    ProviderContainer.defaultRetry(retryCount, error, maxRetries: 3);
