import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { defineSecret } from 'firebase-functions/params';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import {
  TEST_NOTICE,
  TOPIC_OF,
  expenseBody,
  parseTransfers,
  pushMessage,
  recipients,
  settleRequestBody,
  settledBody,
  staleTargets,
} from './notify.js';

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

// ---- 푸시 알림 ----
// 앱을 쓰는 동행자(trips.memberUids)의 기기(users/{uid}.fcmTokens)로 보낸다. 알린 사람 자신은 빼고,
// users/{uid}.notify에서 그 묶음을 끈 사람도 뺀다.

/** 여행 문서와 멤버(이름) 목록. */
async function loadTrip(tripId) {
  const db = getFirestore();
  const [trip, members] = await Promise.all([
    db.doc(`trips/${tripId}`).get(),
    db.collection(`trips/${tripId}/members`).get(),
  ]);
  return {
    trip: trip.exists ? trip.data() : null,
    members: members.docs.map((d) => ({ id: d.id, ...d.data() })),
  };
}

/** [actorUid]를 뺀 여행의 앱 사용자 중 [type] 알림을 받을 기기. */
async function targetsOf(trip, { actorUid, type }) {
  const uids = (trip.memberUids ?? []).filter((uid) => uid !== actorUid);
  if (uids.length === 0) return [];
  const db = getFirestore();
  const snaps = await db.getAll(...uids.map((uid) => db.doc(`users/${uid}`)));
  const users = snaps.map((s) => ({ uid: s.id, data: s.data() ?? {} }));
  return recipients(users, { actorUid, topic: TOPIC_OF[type] });
}

/** 보내고, 더 보낼 수 없게 된 토큰은 그 사람 문서에서 지운다. */
async function deliver(targets, messageFor) {
  if (targets.length === 0) return 0;
  const result = await getMessaging().sendEach(targets.map(messageFor));
  const stale = staleTargets(targets, result.responses);
  const db = getFirestore();
  await Promise.all(
    stale.map((t) => db.doc(`users/${t.uid}`).update({ fcmTokens: FieldValue.arrayRemove(t.token) })),
  );
  if (result.failureCount > stale.length) {
    logger.warn('Some pushes failed', {
      errors: result.responses.filter((r) => !r.success).map((r) => r.error?.code),
    });
  }
  return result.successCount;
}

const nameOf = (members, uid) => members.find((m) => m.uid === uid)?.name ?? '동행자';

/** 동행자가 지출을 기록하면 (오프라인에서 기록해 나중에 올라와도) 나머지 앱 사용자에게 알린다. */
export const notifyExpense = onDocumentCreated(
  { document: 'trips/{tripId}/expenses/{expenseId}', region: 'asia-northeast3' },
  async (event) => {
    const expense = event.data?.data();
    if (!expense) return;
    const { tripId, expenseId } = event.params;
    const { trip, members } = await loadTrip(tripId);
    if (!trip) return;
    const actorUid = expense.createdBy;
    const targets = await targetsOf(trip, { actorUid, type: 'expense' });
    const notice = {
      title: trip.name,
      body: expenseBody({
        actorName: nameOf(members, actorUid),
        title: expense.title || '지출',
        totalMinor: expense.totalMinor ?? 0,
        currency: expense.currency ?? 'KRW',
      }),
    };
    const sent = await deliver(targets, (t) =>
      pushMessage(t.token, notice, { tripId, type: 'expense', expenseId }),
    );
    logger.info('notifyExpense', { tripId, expenseId, targets: targets.length, sent });
  },
);

/**
 * 앱이 정산 요청(정산 요청 보내기)과 정산 완료 때 부른다.
 * 송금 목록은 앱이 계산해서 보내고, 받는 사람마다 자기 몫만 알린다.
 */
export const sendTripNotice = onCall(
  { region: 'asia-northeast3', maxInstances: 5 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in first');
    const { tripId, type } = request.data ?? {};
    if (typeof tripId !== 'string' || !tripId || !['settleRequest', 'settled'].includes(type)) {
      throw new HttpsError('invalid-argument', 'tripId and a known type are required');
    }
    const { trip, members } = await loadTrip(tripId);
    if (!trip || !(trip.memberUids ?? []).includes(uid)) {
      throw new HttpsError('permission-denied', 'Not a member of this trip');
    }
    const actorName = nameOf(members, uid);
    const data = { tripId, type };

    let messageFor;
    if (type === 'settled') {
      const count = request.data.count;
      if (!Number.isInteger(count) || count < 1 || count > 10000) {
        throw new HttpsError('invalid-argument', 'count must be a positive integer');
      }
      const notice = { title: trip.name, body: settledBody({ actorName, count }) };
      messageFor = (t) => pushMessage(t.token, notice, data);
    } else {
      const transfers = parseTransfers(request.data.transfers);
      if (!transfers) throw new HttpsError('invalid-argument', 'transfers are malformed');
      const names = Object.fromEntries(members.map((m) => [m.id, m.name]));
      messageFor = (t) => {
        const memberId = members.find((m) => m.uid === t.uid)?.id;
        const body = settleRequestBody({ requesterName: actorName, memberId, transfers, names });
        return pushMessage(t.token, { title: trip.name, body }, data);
      };
    }

    const targets = await targetsOf(trip, { actorUid: uid, type });
    const sent = await deliver(targets, messageFor);
    logger.info('sendTripNotice', { tripId, type, targets: targets.length, sent });
    return { sent };
  },
);

/**
 * MY → 알림의 "테스트 알림 보내기". 부른 사람의 이 기기 토큰으로만 보낸다 (저장된 토큰이어야 한다).
 * 홈 화면으로 나갈 시간을 주려고 [delaySeconds](최대 10초) 뒤에 보낸다.
 * 앱이 백그라운드로 가서 응답을 못 받아도 볼 수 있게 결과를 users/{uid}.pushTest에 남긴다.
 */
export const sendTestNotice = onCall(
  { region: 'asia-northeast3', maxInstances: 5 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in first');
    const token = request.data?.token;
    if (typeof token !== 'string' || !token) {
      throw new HttpsError('invalid-argument', 'token is required');
    }
    const delaySeconds = Math.min(Math.max(Number(request.data?.delaySeconds) || 0, 0), 10);
    const userRef = getFirestore().doc(`users/${uid}`);
    const user = (await userRef.get()).data() ?? {};
    if (!(user.fcmTokens ?? []).includes(token)) {
      throw new HttpsError('failed-precondition', 'This device token is not saved');
    }
    await new Promise((resolve) => setTimeout(resolve, delaySeconds * 1000));

    let result;
    try {
      await getMessaging().send(pushMessage(token, TEST_NOTICE, { type: 'test' }));
      result = { ok: true };
    } catch (e) {
      result = { ok: false, code: e.code ?? 'unknown' };
      logger.warn('Test push failed', { code: result.code, message: e.message });
      if (staleTargets([{ uid, token }], [{ success: false, error: e }]).length) {
        await userRef.update({ fcmTokens: FieldValue.arrayRemove(token) });
      }
    }
    await userRef.set({ pushTest: { ...result, at: new Date().toISOString() } }, { merge: true });
    logger.info('sendTestNotice', result);
    return result;
  },
);
