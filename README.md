# travelen

여행 모임 가계부 · 정산 앱 (Flutter, Android · iOS).

## 1단계: 영수증 인식

```
촬영 ─ OS 문서 스캐너 (테두리 검출 · 원근 보정)
     └ Android: ML Kit Document Scanner / iOS: VisionKit   (flutter_doc_scanner)
압축 ─ 짧은 변 1600px JPEG                                  (flutter_image_compress)
인식 ─ Gemini, JSON 스키마 강제                              (firebase_ai, Firebase AI Logic)
검산 ─ Σ(품목 − 품목할인) + 별도세금 + 봉사료 + 팁 − 전체할인 = 총액
확인 ─ 사용자가 고친 뒤 저장 (자동 저장 안 함)                 → Firestore
```

- 금액은 전부 통화별 최소 단위 정수로 저장한다 (`lib/core/money/currency.dart`).
- 인식기는 `ReceiptParser` 인터페이스 뒤에 있다. 나중에 온디바이스 OCR 구현으로 바꿔 끼운다.
- 품목마다 `participantIds`가 있어서 2단계에서 품목 단위로 나눠 낼 수 있다.

## Firebase 설정 (travelen-468bc)

1. AI Logic → 시작하기 → Gemini Developer API
2. Firestore Database 만들기 (asia-northeast3) 후 규칙 배포: `firebase deploy --only firestore:rules`
3. Authentication → 로그인 방법 → 익명 사용
4. App Check → 앱 → iOS·Android 앱 각각 ⋮ → 디버그 토큰 관리 → `dart_defines.local.json`의 `APP_CHECK_DEBUG_TOKEN` 등록
   (출시 전: iOS App Attest, Android Play Integrity 등록 후 AI Logic에 App Check 적용)

## 실행

```bash
flutter run --dart-define-from-file=dart_defines.local.json
```

`dart_defines.local.json`은 git에 올리지 않는다. 없으면 `{"APP_CHECK_DEBUG_TOKEN": "<uuidgen 결과>"}`로 만든다.
Xcode 27에서는 `flutter build ios --simulator`가 x86_64 때문에 실패하니 시뮬레이터는 `flutter run`으로 띄운다.

## 인식 정확도 평가

Wikimedia Commons의 자유 라이선스 영수증 사진(`tool/receipt_eval/cases.json`)으로
통화 · 총액 · 품목 수 · 검산 · 여러 장 감지를 확인한다. 사진은 처음 실행할 때 받는다.

```bash
dart run tool/receipt_eval/eval.dart --model gemini-3.5-flash --model gemini-3.5-flash-lite
```

AI Logic에 App Check가 적용돼 있어서 평가 도구도 `dart_defines.local.json`의 디버그 토큰을 쓴다.

인식 모델은 `receiptModels`(지금은 `gemini-3.5-flash` 하나)다. 여러 개를 두면 한도 초과·혼잡일 때 다음 모델로 넘어간다.
실측 비용은 영수증 1장에 약 4.3원(lite 약 2.9원)이고, 2027-01-01부터 flash 단가가 두 배가 된다.
Gemini API는 AI Studio 선불 크레딧으로 결제한다 (https://aistudio.google.com/billing).
Gemini 2.5 계열은 신규 프로젝트에서 쓸 수 없다.

## 앱 정보

- 패키지 / 번들 ID: `com.preper.tripN` (Firebase 앱도 이 ID로 등록됨)
- 앱 아이콘: `assets/icon/`, 다시 만들 때는 `tool/make_app_icon.py` → `dart run flutter_launcher_icons`
