import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  expenseBody,
  formatMoney,
  parseTransfers,
  pushMessage,
  recipients,
  settleRequestBody,
  settledBody,
  staleTargets,
} from './notify.js';

describe('formatMoney', () => {
  test('matches the app: won after the number, other currencies with a symbol', () => {
    assert.equal(formatMoney(12500, 'KRW'), '12,500원');
    assert.equal(formatMoney(3960, 'JPY'), '¥3,960');
    assert.equal(formatMoney(1250, 'USD'), '$12.50');
    // TWD·IDR은 공식 2자리지만 앱처럼 소수점 없이 쓴다.
    assert.equal(formatMoney(350, 'TWD'), 'NT$350');
    assert.equal(formatMoney(150000, 'IDR'), 'Rp150,000');
    assert.equal(formatMoney(1999, 'XYZ'), 'XYZ19.99');
  });
});

describe('bodies', () => {
  test('an expense names who recorded it, what, and how much', () => {
    assert.equal(
      expenseBody({ actorName: '민수', title: '이치란 라멘', totalMinor: 3960, currency: 'JPY' }),
      '민수님이 지출을 기록했어요 · 이치란 라멘 ¥3,960',
    );
  });

  const names = { a: '지민', b: '민수', c: '서연', d: '도윤' };
  const transfers = [
    { from: 'b', to: 'a', amount: 23069 },
    { from: 'c', to: 'a', amount: 5000 },
  ];

  test('a settlement request tells each person their own part', () => {
    const body = (memberId) =>
      settleRequestBody({ requesterName: '지민', memberId, transfers, names });
    assert.equal(body('b'), '지민님이 정산을 요청했어요. 지민님에게 23,069원 보내 주세요');
    assert.equal(
      body('a'),
      '지민님이 정산을 요청했어요. 민수님에게서 23,069원, 서연님에게서 5,000원을 받아요',
    );
    assert.equal(body('d'), '지민님이 정산을 요청했어요');
  });

  test('settling names who marked how many expenses', () => {
    assert.equal(
      settledBody({ actorName: '서연', count: 5 }),
      '서연님이 지출 5건을 정산 완료로 표시했어요',
    );
  });
});

describe('parseTransfers', () => {
  test('keeps well-formed transfers only', () => {
    assert.deepEqual(parseTransfers([{ from: 'b', to: 'a', amount: 100, extra: 1 }]), [
      { from: 'b', to: 'a', amount: 100 },
    ]);
    assert.equal(parseTransfers([]), null);
    assert.equal(parseTransfers('nope'), null);
    assert.equal(parseTransfers([{ from: 'b', to: 'a', amount: -1 }]), null);
    assert.equal(parseTransfers([{ from: 'b', to: 'a', amount: 1.5 }]), null);
    assert.equal(parseTransfers(Array(51).fill({ from: 'b', to: 'a', amount: 1 })), null);
  });
});

describe('recipients', () => {
  const users = [
    { uid: 'alice', data: { fcmTokens: ['a1'] } },
    { uid: 'bob', data: { fcmTokens: ['b1', 'b2'], notify: { expense: true } } },
    { uid: 'carol', data: { fcmTokens: ['c1'], notify: { expense: false, settlement: true } } },
    { uid: 'dave', data: {} },
  ];

  test('everyone but the actor, every device, unless they turned the topic off', () => {
    assert.deepEqual(recipients(users, { actorUid: 'alice', topic: 'expense' }), [
      { uid: 'bob', token: 'b1' },
      { uid: 'bob', token: 'b2' },
    ]);
    assert.deepEqual(
      recipients(users, { actorUid: 'alice', topic: 'settlement' }).map((r) => r.token),
      ['b1', 'b2', 'c1'],
    );
  });
});

describe('pushMessage', () => {
  test('groups a trip in one thread and carries what the app needs to open it', () => {
    const message = pushMessage('t', { title: '도쿄', body: '...' }, { tripId: 'trip1', type: 'expense' });
    assert.equal(message.token, 't');
    assert.deepEqual(message.data, { tripId: 'trip1', type: 'expense' });
    assert.equal(message.apns.payload.aps['thread-id'], 'trip1');
    // 저전력 모드에서도 바로 보이게
    assert.equal(message.apns.headers['apns-priority'], '10');
  });
});

describe('test notice', () => {
  test('is not grouped under any trip', () => {
    const message = pushMessage('t', { title: '테스트', body: '...' }, { type: 'test' });
    assert.deepEqual(message.apns.payload.aps, { sound: 'default' });
    assert.deepEqual(message.data, { type: 'test' });
  });
});

describe('staleTargets', () => {
  test('drops tokens FCM no longer knows, keeps ones that failed for a moment', () => {
    const targets = [
      { uid: 'a', token: 'gone' },
      { uid: 'a', token: 'ok' },
      { uid: 'b', token: 'busy' },
    ];
    const responses = [
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
      { success: true },
      { success: false, error: { code: 'messaging/internal-error' } },
    ];
    assert.deepEqual(staleTargets(targets, responses), [{ uid: 'a', token: 'gone' }]);
  });
});
