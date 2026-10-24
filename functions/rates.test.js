import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { parseKoreaExim, previousDay, resolveRates, todayInSeoul } from './rates.js';

const row = (cur_unit, deal_bas_r) => ({ result: 1, cur_unit, deal_bas_r });

describe('parseKoreaExim', () => {
  test('reads base rates per one unit, splitting 100-unit currencies', () => {
    const rates = parseKoreaExim([
      row('USD', '1,385.5'),
      row('JPY(100)', '925.12'),
      row('IDR(100)', '8.6'),
      row('KRW', '1'),
    ]);
    assert.deepEqual(rates, { USD: 1385.5, JPY: 9.2512, IDR: 0.086 });
  });

  test('a non-business day (empty or null rows) has no data', () => {
    assert.equal(parseKoreaExim([]), null);
    assert.equal(parseKoreaExim([{ result: 1, cur_unit: null, deal_bas_r: null }]), null);
  });

  test('API errors are reported, not mistaken for a holiday', () => {
    assert.throws(() => parseKoreaExim([{ result: 3, cur_unit: null }]), { code: 'auth' });
    assert.throws(() => parseKoreaExim([{ result: 4, cur_unit: null }]), { code: 'quota' });
  });
});

describe('dates', () => {
  test('today follows Seoul time', () => {
    // 2026-10-23 16:00 UTC = 2026-10-24 01:00 KST
    assert.equal(todayInSeoul(new Date('2026-10-23T16:00:00Z')), '2026-10-24');
  });

  test('previous day crosses month and year boundaries', () => {
    assert.equal(previousDay('2026-03-01'), '2026-02-28');
    assert.equal(previousDay('2026-01-01'), '2025-12-31');
  });
});

describe('resolveRates', () => {
  // 2026-10-23(금)은 영업일, 24·25일은 주말.
  const published = { '2026-10-23': { USD: 1385.5 }, '2026-10-26': { USD: 1390 } };

  function setup(initial = {}) {
    const docs = new Map(Object.entries(initial));
    const calls = [];
    return {
      docs,
      calls,
      store: { get: async (d) => docs.get(d) ?? null, put: async (d, v) => void docs.set(d, v) },
      fetchDay: async (d) => {
        calls.push(d);
        return published[d] ?? null;
      },
    };
  }

  test('a business day is fetched once and cached', async () => {
    const s = setup();
    const first = await resolveRates({ date: '2026-10-23', today: '2026-10-30', ...s });
    assert.deepEqual(first, { date: '2026-10-23', effectiveDate: '2026-10-23', krwPer: { USD: 1385.5 } });
    await resolveRates({ date: '2026-10-23', today: '2026-10-30', ...s });
    assert.deepEqual(s.calls, ['2026-10-23']);
  });

  test('a past weekend uses Friday and remembers that', async () => {
    const s = setup();
    const sunday = await resolveRates({ date: '2026-10-25', today: '2026-10-30', ...s });
    assert.equal(sunday.effectiveDate, '2026-10-23');
    assert.deepEqual(s.calls, ['2026-10-25', '2026-10-24', '2026-10-23']);

    await resolveRates({ date: '2026-10-24', today: '2026-10-30', ...s });
    assert.deepEqual(s.calls, ['2026-10-25', '2026-10-24', '2026-10-23']);
  });

  test('today before publication falls back without caching today', async () => {
    const s = setup();
    const rates = await resolveRates({ date: '2026-10-24', today: '2026-10-24', ...s });
    assert.equal(rates.effectiveDate, '2026-10-23');
    assert.equal(s.docs.has('2026-10-24'), false);
  });

  test('a receipt dated ahead of Seoul is treated as Seoul today', async () => {
    const s = setup();
    const rates = await resolveRates({ date: '2026-10-27', today: '2026-10-26', ...s });
    assert.equal(rates.date, '2026-10-26');
    assert.equal(rates.effectiveDate, '2026-10-26');
  });

  test('gives up after a long stretch without rates', async () => {
    const s = setup();
    await assert.rejects(resolveRates({ date: '2026-09-15', today: '2026-10-30', ...s }), {
      code: 'not-found',
    });
  });
});
