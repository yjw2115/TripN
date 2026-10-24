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

배포하기 전에 앱으로 확인하려면 에뮬레이터를 띄우고 디버그 빌드에 `FIREBASE_EMULATOR`를 준다
(Firestore 8080, Functions 5001).

```bash
PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin:$PATH" firebase emulators:start --only firestore,functions --project travelen-468bc
flutter run --dart-define-from-file=dart_defines.local.json --dart-define=FIREBASE_EMULATOR=localhost
```

Functions 에뮬레이터는 `functions/.secret.local`(git 제외)에서 `KOREAEXIM_AUTHKEY=...`를 읽는다.
파일이 없으면 운영 Secret Manager 값을 가져오려 한다.

## 3단계: 환율 고정

```
rates/{yyyy-MM-dd}              effectiveDate(실제 고시일), krwPer{통화: 1단위당 원}   ← Cloud Functions만 씀
trips/{tripId}                  manualRates{통화: 1단위당 원}                          ← 수출입은행에 없는 통화
trips/{tripId}/expenses/{id}    krwRate, rateSource(koreaexim|manual|krw), rateDate
```

- 지출을 저장할 때 그 영수증 날짜의 한국수출입은행 매매기준율을 지출에 고정한다. 동행자 모두 같은 원화 금액으로 정산한다.
  고칠 때 통화나 날짜가 그대로면 처음 고정한 환율을 바꾸지 않는다.
- 앱은 `rates/{날짜}`를 먼저 읽고, 없을 때만 `exchangeRates` 함수(asia-northeast3)를 부른다. 함수가 받은 환율을 저장해 두어서
  같은 날짜는 모든 사용자가 API를 한 번만 쓴다 (수출입은행 한도: 하루 1,000회).
- 비영업일·고시 전(영업일 11시 전)은 직전 영업일 환율을 쓰고 `effectiveDate`에 그 날짜를 남긴다.
  지난 비영업일은 저장해 두고, 고시 전인 오늘은 저장하지 않는다.
- `JPY(100)`, `IDR(100)`은 1단위로 나눠 저장한다. 위안화는 수출입은행이 CNH로 고시해서 CNY를 CNH로 찾는다.
- 수출입은행에 없는 통화(VND, PHP, TWD 등)는 여행에서 한 번 직접 정한다 (확인 화면의 "환율을 정해 주세요").
- 오프라인으로 저장했거나 1.0.0+3 이전 지출처럼 환율이 없는 지출은 홈 화면이 열려 있을 때 채운다 (`rateBackfillProvider`).

```bash
# API 키는 Secret Manager에만 둔다 (입력은 가려진다)
firebase functions:secrets:set KOREAEXIM_AUTHKEY --project travelen-468bc
cd functions && npm install && npm test
firebase deploy --only functions,firestore:rules --project travelen-468bc
```

Functions 패키지는 firebase-admin 13을 쓴다. 14는 이 맥의 Node 22.11에서 ESM 의존성(jose)을 불러오지 못한다.

## 4단계: 정산

```
trips/{tripId}/members/{id}     account{bank, number, holder}   ← 받을 계좌 (여행 멤버끼리만 보임)
trips/{tripId}/expenses/{id}    participantIds                  ← 함께 쓴 사람 (저장할 때 정함)
  receipt.items[].participantIds                                ← 같이 먹은 사람 (비면 함께 쓴 사람 모두)
```

- 계산은 `lib/features/settlement/domain/settlement.dart`의 순수 함수 (`settle`, `sharesOf`, `allocate`).
  - 품목이 있으면 품목마다 같이 먹은 사람끼리 나누고, 그 비율대로 지출 총액(세금·봉사료·팁·할인 포함)을 나눈다.
  - 품목이 없으면 함께 쓴 사람끼리 똑같이 나눈다. 예전 지출(participantIds 없음)은 지금 멤버 전원.
  - 몫의 합은 언제나 원화 총액과 같다. 남는 1원은 버린 소수점이 큰 사람부터, 같으면 결제자가 가져간다.
  - 환율을 못 정한 지출은 빼고 건수를 보여준다.
  - 보낼 돈은 가장 많이 보낼 사람과 받을 사람을 차례로 짝지어 최대 (인원 − 1)번으로 끝낸다.
- 정산 화면(홈의 "정산하기"): 보낼 돈 → 금액 복사 / 계좌와 금액 복사 / 받을 계좌 등록, 각자 낸 돈·쓴 돈, 정산 요청 메시지 공유.
- 외화를 쓴 여행이면 금액마다 현지 화폐로 얼마인지도 보여준다 ("≈ ¥9,000"). 가장 많이 쓴 외화가 기본이고 바꿀 수 있다.
  환율은 그 통화로 쓴 지출의 평균 (원화 합계 ÷ 현지 화폐 합계). 복사와 정산 요청 메시지는 원화로만 한다.
- 함께 쓴 사람에만 들어 있는 동행자는 지울 수 있다 (그 지출들에서 빠짐). 결제자나 같이 먹은 사람으로 콕 집힌 동행자는 지울 수 없다.

### 초대 링크

`https://travelen-468bc.web.app/join/{코드}` (초대 메시지에 들어간다)

- 앱이 있으면 iOS Universal Link / Android App Link로 앱의 `/join/{코드}` 경로가 열리고, 코드 입력 없이 여행 확인으로 간다.
  - iOS: `ios/Runner/Runner.entitlements`의 `applinks:travelen-468bc.web.app` ↔ `hosting/.well-known/apple-app-site-association` (팀 7ZQN43985N)
  - Android: `AndroidManifest.xml`의 autoVerify intent-filter ↔ `hosting/.well-known/assetlinks.json`
    (업로드 키·디버그 키 지문. **Play 앱 서명 키 지문은 Play Console → 앱 무결성에서 복사해 추가해야** Play에서 받은 앱이 바로 열린다)
- 카카오톡 인앱 브라우저는 Universal Link를 앱으로 넘기지 않아서 `hosting/join.html`이 열린다.
  이 페이지가 앱 스킴(`tripn://app/join/{코드}`, Android는 intent://)으로 앱을 열고, 앱이 없으면 코드와 설치 방법을 보여준다.
- 앱은 경로만 본다 (Flutter 딥 링크 → go_router `/join/:code`). 스킴의 호스트(`app`)는 쓰지 않는다.
- 호스팅을 배포해야 링크가 동작한다: `firebase deploy --only hosting --project travelen-468bc`

## 5단계: 메뉴판으로 주문

홈의 "메뉴판으로 주문" → 메뉴판 찍기(여러 장 가능) → 한국어로 번역된 메뉴에서 고르기 → 미리 보는 영수증 → 주문 확인(영수증 확인 화면과 같음) → 지출로 저장 (`source: 'menu'`, 영수증 없이 정산)

```
trips/{tripId}/menus/{menuId}   storeName, currency, countryCode, taxIncluded, taxRatePercent,
                                serviceChargePercent, items[{id, name, nameKo, descriptionKo, section, priceMinor}]
```

- 인식: `lib/features/menu/data/menu_prompt.dart` (Gemini, 영수증과 같은 모델·호출 방식). 크기·온도별 가격은 메뉴를 나누고("카페라테 (아이스)"),
  가격대("600-800-1,000")는 소/중/대로 나눈다. 한국 메뉴판의 "4.5"(4,500원), "12"(12,000원), 싯가도 규칙에 있다.
- 세금·봉사료: 메뉴판에 적힌 대로(税込/税抜, "++", "service charge"). 적혀 있지 않으면 나라 관행을 따른다
  (미국·캐나다는 별도, 그 밖은 포함). 별도인데 세율이 없으면 일본 10, 태국 7, 싱가포르 9, 말레이시아 6. 메뉴 화면에서 고칠 수 있다.
- 미리 보는 영수증: 소계 + 봉사료(소계 기준) + 별도 세금(소계 + 봉사료 기준) + 팁. 미국·캐나다는 팁 15/18/20% 칩.
- 찍은 메뉴판은 여행에 가게별로 남아서 같은 가게에서 다시 주문할 때 다시 찍지 않는다. 메뉴 이름·가격·가게 이름을 고칠 수 있다.
- 인식 확인: `dart run tool/menu_eval/eval.dart` (Wikimedia Commons의 일본·태국·베트남·미국·대만·한국 메뉴판, `tool/menu_eval/cases.json`)

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
