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

## 2단계: 여행 · 동행자

```
users/{uid}                         currentTripId (고른 여행)
trips/{tripId}                      name, ownerId, memberUids(앱 사용자 uid), inviteCode
trips/{tripId}/members/{memberId}   name, uid (이름만 있는 동행자는 null)
trips/{tripId}/expenses/{id}        ... payerId(멤버 id), receipt.items[].participantIds(멤버 id)
invites/{code}                      tripId, tripName
```

- 결제자와 품목 참여자는 uid가 아니라 **멤버 id**를 가리킨다. 그래서 앱을 쓰지 않는 사람도 이름만으로 정산에 넣을 수 있다.
- 앱 사용자가 스스로 만든 멤버(여행을 만들거나 초대로 들어온 사람)는 문서 id가 uid다. 이름으로 추가한 동행자는 자동 id다.
- 초대: 여행 설정 → 초대 코드 보내기 → 받은 사람이 홈의 여행 이름 → 초대 코드로 참여하기.
  참여한 뒤 이름만 있던 동행자 중 자기를 고르면 그 멤버에 uid가 채워져 기록이 이어진다.
- 나가기: 내 멤버는 이름만 있는 동행자로 남는다 (지출 기록이 깨지지 않게). 소유자는 나갈 수 없고 여행을 지운다.
- 1.0.0+3까지 만든 여행(`memberIds`)은 앱이 처음 열 때 새 구조로 옮긴다. 옛 지출의 payerId(uid)가 그대로 내 멤버 id가 된다.

### 보안 규칙 테스트

에뮬레이터에서 돈다. firebase-tools가 Java 21 이상을 요구하는데, 이 맥의 기본 java는 17이라
`JAVA_HOME`으로 Android Studio에 든 JBR을 넘긴다 (`npm test`가 그 java를 먼저 쓴다).

```bash
cd tool/firestore_rules && npm install
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" npm test
```

규칙을 배포하기 전에 앱으로 확인하려면 에뮬레이터를 띄우고 디버그 빌드에 `FIRESTORE_EMULATOR`를 준다.

```bash
PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin:$PATH" firebase emulators:start --only firestore --project travelen-468bc
flutter run --dart-define-from-file=dart_defines.local.json --dart-define=FIRESTORE_EMULATOR=localhost:8080
```

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
