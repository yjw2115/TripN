// 한국수출입은행 환율(AP01)을 날짜별로 받아 Firestore rates/{yyyy-MM-dd}에 모아 둔다.
// Firebase에 의존하지 않게 저장소(store)와 API 호출(fetchDay)을 밖에서 받는다.

export const API_URL = 'https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON';

/** 비영업일이 길게 이어져도(설·추석 연휴) 직전 영업일을 찾을 만큼. */
const MAX_LOOKBACK_DAYS = 10;

/** 이보다 오래된 날짜는 받지 않는다 (하루 1,000회 호출 한도를 오래된 날짜로 낭비하지 않게). */
export const EARLIEST_DATE = '2015-01-01';

export class RateApiError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/** 서울 기준 오늘 (yyyy-MM-dd). 수출입은행 고시는 서울 날짜로 나온다. */
export function todayInSeoul(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(now);
}

export function previousDay(date) {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

export function isDateKey(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

/**
 * AP01 응답을 { 통화코드: 1단위당 원화 } 로 바꾼다. 데이터가 없으면(비영업일, 고시 전) null.
 * "JPY(100)"처럼 100단위로 오는 통화는 1단위로 나눈다. 금액에는 "1,385.5"처럼 쉼표가 있다.
 */
export function parseKoreaExim(rows) {
  if (!Array.isArray(rows) || rows.length === 0) return null;
  const result = rows[0]?.result;
  if (result === 2) throw new RateApiError('bad-request', 'Invalid data code');
  if (result === 3) throw new RateApiError('auth', 'Invalid or expired auth key');
  if (result === 4) throw new RateApiError('quota', 'Daily call limit reached');
  const krwPer = {};
  for (const row of rows) {
    if (row?.result !== 1 || typeof row.cur_unit !== 'string' || row.deal_bas_r == null) continue;
    const match = /^([A-Z]{3})(?:\((\d+)\))?$/.exec(row.cur_unit.trim());
    if (!match || match[1] === 'KRW') continue;
    const rate = Number(String(row.deal_bas_r).replaceAll(',', '')) / Number(match[2] ?? 1);
    if (Number.isFinite(rate) && rate > 0) krwPer[match[1]] = rate;
  }
  return Object.keys(krwPer).length > 0 ? krwPer : null;
}

export async function fetchKoreaExim(date, authKey) {
  const url = new URL(API_URL);
  url.search = new URLSearchParams({ authkey: authKey, searchdate: date, data: 'AP01' }).toString();
  const response = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new RateApiError('unavailable', `HTTP ${response.status}`);
  return parseKoreaExim(await response.json());
}

/**
 * [date]에 쓸 환율. 그날 고시가 없으면 직전 영업일 것을 쓰고 effectiveDate에 그 날짜를 남긴다.
 *
 * 영업일 환율은 그 날짜 문서로 저장한다. 지난 비영업일도 직전 영업일 환율을 가리키는 문서로
 * 저장해 두고(바뀔 일이 없으니), 고시 전인 오늘은 저장하지 않는다(11시쯤 오늘 것이 나온다).
 * 서울보다 날짜가 앞선 곳(뉴질랜드 등)의 영수증은 서울 오늘로 본다.
 */
export async function resolveRates({ date, today, store, fetchDay }) {
  const target = date > today ? today : date;
  const cached = await store.get(target);
  if (cached) return cached;

  const skipped = [];
  let day = target;
  for (let i = 0; i <= MAX_LOOKBACK_DAYS; i++, day = previousDay(day)) {
    let found = i === 0 ? null : await store.get(day);
    if (!found) {
      const krwPer = await fetchDay(day);
      if (krwPer) {
        found = { date: day, effectiveDate: day, krwPer };
        await store.put(day, found);
      }
    }
    if (found) {
      const { effectiveDate, krwPer } = found;
      // 지나 온 비영업일(연휴 중간 날짜 포함)도 같은 환율을 가리키게 남긴다.
      for (const gap of skipped) {
        if (gap < today) await store.put(gap, { date: gap, effectiveDate, krwPer });
      }
      return { date: target, effectiveDate, krwPer };
    }
    skipped.push(day);
  }
  throw new RateApiError('not-found', `No rates within ${MAX_LOOKBACK_DAYS} days before ${target}`);
}
