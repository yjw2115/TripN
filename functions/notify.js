/**
 * 푸시 알림 문구와 받을 기기 고르기. Firestore·FCM 없이 테스트할 수 있게 index.js와 나눈다.
 * 종류(type)와 끌 수 있는 묶음(topic) 이름은 앱(lib/features/notify, NotifyTopic)과 같다.
 */

/** 알림 종류 → 사용자가 끌 수 있는 묶음 (users/{uid}.notify의 키). */
export const TOPIC_OF = { expense: 'expense', settleRequest: 'settlement', settled: 'settlement' };

/** 앱의 Currency.all과 같은 표 (lib/core/money/currency.dart). [소수 자릿수, 기호] */
const CURRENCIES = {
  KRW: [0, '₩'], JPY: [0, '¥'], USD: [2, '$'], EUR: [2, '€'], CNY: [2, '¥'],
  VND: [0, '₫'], THB: [2, '฿'], PHP: [2, '₱'], TWD: [0, 'NT$'], HKD: [2, 'HK$'],
  SGD: [2, 'S$'], MYR: [2, 'RM'], IDR: [0, 'Rp'], GBP: [2, '£'], CHF: [2, 'CHF'],
  AUD: [2, 'A$'], CAD: [2, 'C$'], NZD: [2, 'NZ$'], MOP: [2, 'MOP$'], MNT: [0, '₮'],
  TRY: [2, '₺'], CZK: [2, 'Kč'], HUF: [0, 'Ft'], AED: [2, 'AED'],
};

/** 앱의 formatMoney와 같은 모양: "12,500원", "¥980", "$12.50". 모르는 통화는 소수 2자리. */
export function formatMoney(minor, code) {
  const [decimals, symbol] = CURRENCIES[code] ?? [2, code];
  const text = new Intl.NumberFormat('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(minor / 10 ** decimals);
  return code === 'KRW' ? `${text}원` : `${symbol}${text}`;
}

export function expenseBody({ actorName, title, totalMinor, currency }) {
  return `${actorName}님이 지출을 기록했어요 · ${title} ${formatMoney(totalMinor, currency)}`;
}

/**
 * 정산 요청을 받는 사람마다 자기 몫을 알려준다.
 * [transfers]는 멤버 id 기준 {from, to, amount(원)}, [names]는 멤버 id → 이름.
 */
export function settleRequestBody({ requesterName, memberId, transfers, names }) {
  const name = (id) => `${names[id] ?? '동행자'}님`;
  const won = (amount) => formatMoney(amount, 'KRW');
  const head = `${requesterName}님이 정산을 요청했어요`;
  const pays = transfers.filter((t) => t.from === memberId);
  if (pays.length) {
    return `${head}. ${pays.map((t) => `${name(t.to)}에게 ${won(t.amount)}`).join(', ')} 보내 주세요`;
  }
  const gets = transfers.filter((t) => t.to === memberId);
  if (gets.length) {
    return `${head}. ${gets.map((t) => `${name(t.from)}에게서 ${won(t.amount)}`).join(', ')}을 받아요`;
  }
  return head;
}

export function settledBody({ actorName, count }) {
  return `${actorName}님이 지출 ${count}건을 정산 완료로 표시했어요`;
}

/** MY → 알림의 테스트 알림. */
export const TEST_NOTICE = {
  title: '여행N 알림 테스트',
  body: '이 알림이 보이면 이 기기에서 동행자 소식을 받을 수 있어요',
};

/** 앱이 보낸 정산 요청의 송금 목록. 모양이 틀리면 null. */
export function parseTransfers(input) {
  if (!Array.isArray(input) || input.length === 0 || input.length > 50) return null;
  const ok = input.every(
    (t) =>
      t && typeof t.from === 'string' && typeof t.to === 'string' &&
      Number.isInteger(t.amount) && t.amount > 0,
  );
  return ok ? input.map(({ from, to, amount }) => ({ from, to, amount })) : null;
}

/**
 * 알림을 받을 기기. [users]는 {uid, data(users/{uid} 문서)}.
 * 알린 사람 자신과, 이 묶음의 알림을 끈 사람은 뺀다 (끄기 전에는 켜져 있다).
 */
export function recipients(users, { actorUid, topic }) {
  return users
    .filter(({ uid, data }) => uid !== actorUid && data?.notify?.[topic] !== false)
    .flatMap(({ uid, data }) =>
      (Array.isArray(data?.fcmTokens) ? data.fcmTokens : [])
        .filter((token) => typeof token === 'string' && token)
        .map((token) => ({ uid, token })),
    );
}

/**
 * FCM 메시지. data는 앱의 TripNotice.fromData가 읽는다 (값은 모두 문자열이어야 한다).
 * 같은 여행 알림은 iOS에서 한 묶음(thread-id)으로 모인다. 여행이 없는 테스트 알림은 묶지 않는다.
 * iOS는 android 블록을 보지 않아서 aps.sound가 없으면 소리 없이 오고, apns-priority 10이어야
 * 저전력 모드에서도 미뤄지지 않는다 (notification_class 앱과 같은 설정).
 */
export function pushMessage(token, { title, body }, data) {
  const aps = { sound: 'default', ...(data.tripId ? { 'thread-id': data.tripId } : {}) };
  return {
    token,
    notification: { title, body },
    data,
    apns: { headers: { 'apns-priority': '10' }, payload: { aps } },
    // 채널은 앱(MainActivity)이 만든다. 없으면 FCM 기본 채널로 간다.
    android: { priority: 'high', notification: { channelId: 'trip_activity', sound: 'default' } },
  };
}

/** 보낼 수 없게 된 토큰 (앱을 지웠거나 토큰이 바뀌었다). 지워서 다음에 또 보내지 않는다. */
const STALE_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** sendEach의 결과(responses)에서 지울 토큰을 고른다. 잠깐의 서버 오류로 실패한 토큰은 남긴다. */
export function staleTargets(targets, responses) {
  return targets.filter((_, i) => {
    const r = responses[i];
    return r && !r.success && STALE_TOKEN_CODES.has(r.error?.code);
  });
}
