import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import {
  EARLIEST_DATE,
  RateApiError,
  fetchKoreaExim,
  isDateKey,
  resolveRates,
  todayInSeoul,
} from './rates.js';

initializeApp();

/** `firebase functions:secrets:set KOREAEXIM_AUTHKEY`로 넣는다. 앱과 저장소에는 두지 않는다. */
const authKey = defineSecret('KOREAEXIM_AUTHKEY');

/**
 * 앱이 rates/{date}를 먼저 읽고, 없을 때만 부른다. 받은 환율은 rates/{date}에 남겨서
 * 같은 날짜는 모든 사용자가 한 번만 API를 쓴다.
 */
export const exchangeRates = onCall(
  { region: 'asia-northeast3', secrets: [authKey], maxInstances: 5 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first');
    const date = request.data?.date;
    if (!isDateKey(date) || date < EARLIEST_DATE) {
      throw new HttpsError('invalid-argument', 'date must be yyyy-MM-dd on or after 2015-01-01');
    }

    const rates = getFirestore().collection('rates');
    const store = {
      get: async (day) => {
        const snap = await rates.doc(day).get();
        return snap.exists ? snap.data() : null;
      },
      put: (day, value) =>
        rates.doc(day).set({ ...value, source: 'koreaexim', fetchedAt: FieldValue.serverTimestamp() }),
    };

    try {
      const result = await resolveRates({
        date,
        today: todayInSeoul(),
        store,
        fetchDay: (day) => fetchKoreaExim(day, authKey.value()),
      });
      return { date: result.date, effectiveDate: result.effectiveDate, krwPer: result.krwPer };
    } catch (e) {
      logger.error('exchangeRates failed', { date, error: String(e) });
      if (e instanceof RateApiError && e.code === 'not-found') {
        throw new HttpsError('not-found', 'No published rates for that date');
      }
      throw new HttpsError('unavailable', 'Exchange rates are temporarily unavailable');
    }
  },
);
