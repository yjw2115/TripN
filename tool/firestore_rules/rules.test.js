// Firestore 보안 규칙 테스트. 에뮬레이터 위에서 돈다.
//   cd tool/firestore_rules && npm install && npm test
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayRemove,
  arrayUnion,
  collection,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const TRIP = 'trip1';
const CODE = 'K7Q2MX';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-travelen',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

beforeEach(() => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid).firestore();

const member = (name, uid, createdBy) => ({
  name,
  uid,
  createdBy,
  createdAt: serverTimestamp(),
});

/// 앱이 하듯이 여행 + 내 멤버 + 고른 여행을 한 번에 쓴다.
function createTrip(uid, tripId = TRIP) {
  const d = db(uid);
  return writeBatch(d)
    .set(doc(d, 'trips', tripId), {
      name: '도쿄 여행',
      ownerId: uid,
      memberUids: [uid],
      createdAt: serverTimestamp(),
    })
    .set(doc(d, 'trips', tripId, 'members', uid), member('지민', uid, uid))
    .set(doc(d, 'users', uid), { currentTripId: tripId }, { merge: true })
    .commit();
}

function createInvite(uid, code = CODE) {
  const d = db(uid);
  return writeBatch(d)
    .set(doc(d, 'invites', code), {
      tripId: TRIP,
      tripName: '도쿄 여행',
      createdBy: uid,
      createdAt: serverTimestamp(),
    })
    .update(doc(d, 'trips', TRIP), { inviteCode: code })
    .commit();
}

function join(uid, code = CODE) {
  const d = db(uid);
  return writeBatch(d)
    .set(doc(d, 'trips', TRIP, 'members', uid), {
      ...member('새 동행자', uid, uid),
      joinCode: code,
    })
    .update(doc(d, 'trips', TRIP), { memberUids: arrayUnion(uid) })
    .set(doc(d, 'users', uid), { currentTripId: TRIP }, { merge: true })
    .commit();
}

async function addGuest(uid, id, name) {
  const d = db(uid);
  await setDoc(doc(d, 'trips', TRIP, 'members', id), member(name, null, uid));
}

describe('trips', () => {
  test('anyone signed in can create their own trip', async () => {
    await assertSucceeds(createTrip('alice'));
  });

  test('cannot create a trip for someone else', async () => {
    const d = db('alice');
    await assertFails(
      setDoc(doc(d, 'trips', TRIP), {
        name: '도쿄 여행',
        ownerId: 'bob',
        memberUids: ['bob'],
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('only members can read the trip, and the trip list must filter by uid', async () => {
    await createTrip('alice');
    await assertSucceeds(getDoc(doc(db('alice'), 'trips', TRIP)));
    await assertFails(getDoc(doc(db('bob'), 'trips', TRIP)));
    await assertSucceeds(
      getDocs(query(collection(db('alice'), 'trips'), where('memberUids', 'array-contains', 'alice'))),
    );
    await assertFails(getDocs(collection(db('alice'), 'trips')));
  });

  test('members rename the trip but cannot change the owner', async () => {
    await createTrip('alice');
    await assertSucceeds(updateDoc(doc(db('alice'), 'trips', TRIP), { name: '오사카 여행' }));
    await assertFails(updateDoc(doc(db('alice'), 'trips', TRIP), { ownerId: 'bob' }));
    await assertFails(updateDoc(doc(db('alice'), 'trips', TRIP), { name: '' }));
  });

  test('a member cannot add someone else as an app user', async () => {
    await createTrip('alice');
    await assertFails(updateDoc(doc(db('alice'), 'trips', TRIP), { memberUids: arrayUnion('bob') }));
  });
});

describe('guest members', () => {
  test('members add, rename and delete name-only companions', async () => {
    await createTrip('alice');
    const d = db('alice');
    await assertSucceeds(addGuest('alice', 'g1', '민수'));
    await assertSucceeds(updateDoc(doc(d, 'trips', TRIP, 'members', 'g1'), { name: '민수형' }));
    await assertSucceeds(writeBatch(d).delete(doc(d, 'trips', TRIP, 'members', 'g1')).commit());
  });

  test('outsiders cannot read or add members', async () => {
    await createTrip('alice');
    await assertFails(getDocs(collection(db('bob'), 'trips', TRIP, 'members')));
    await assertFails(addGuest('bob', 'g1', '민수'));
  });

  test('a member cannot create an app-user member for someone else', async () => {
    await createTrip('alice');
    const d = db('alice');
    await assertFails(setDoc(doc(d, 'trips', TRIP, 'members', 'bob'), member('밥', 'bob', 'alice')));
    await assertFails(setDoc(doc(d, 'trips', TRIP, 'members', 'g1'), member('밥', 'bob', 'alice')));
  });

  test('a guest member must have an explicit uid field', async () => {
    await createTrip('alice');
    const d = db('alice');
    await assertFails(
      setDoc(doc(d, 'trips', TRIP, 'members', 'g1'), {
        name: '민수',
        createdBy: 'alice',
        createdAt: serverTimestamp(),
      }),
    );
  });
});

describe('invites', () => {
  test('a member creates an invite; anyone can open it by code but not list them', async () => {
    await createTrip('alice');
    await assertSucceeds(createInvite('alice'));
    await assertSucceeds(getDoc(doc(db('bob'), 'invites', CODE)));
    await assertFails(getDocs(collection(db('bob'), 'invites')));
  });

  test('outsiders cannot create an invite for a trip', async () => {
    await createTrip('alice');
    const d = db('bob');
    await assertFails(
      setDoc(doc(d, 'invites', CODE), {
        tripId: TRIP,
        tripName: '도쿄 여행',
        createdBy: 'bob',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('the trip cannot point to an invite code that does not exist', async () => {
    await createTrip('alice');
    await assertFails(updateDoc(doc(db('alice'), 'trips', TRIP), { inviteCode: 'ZZZZZZ' }));
  });

  test('joining with the current code works', async () => {
    await createTrip('alice');
    await createInvite('alice');
    await assertSucceeds(join('bob'));
    await assertSucceeds(getDocs(collection(db('bob'), 'trips', TRIP, 'members')));
  });

  test('joining with a wrong code, or before any invite exists, fails', async () => {
    await createTrip('alice');
    await assertFails(join('bob'));
    await createInvite('alice');
    await assertFails(join('bob', 'AAAAAA'));
  });

  test('knowing the trip id alone is not enough to join', async () => {
    await createTrip('alice');
    await createInvite('alice');
    await assertFails(updateDoc(doc(db('bob'), 'trips', TRIP), { memberUids: arrayUnion('bob') }));
  });

  test('a joiner can only add themselves', async () => {
    await createTrip('alice');
    await createInvite('alice');
    const d = db('bob');
    await assertFails(
      writeBatch(d)
        .set(doc(d, 'trips', TRIP, 'members', 'bob'), { ...member('밥', 'bob', 'bob'), joinCode: CODE })
        .update(doc(d, 'trips', TRIP), { memberUids: arrayUnion('bob', 'carol') })
        .commit(),
    );
  });

  test('a joiner claims a name-only companion and drops the placeholder member', async () => {
    await createTrip('alice');
    await addGuest('alice', 'g1', '밥');
    await createInvite('alice');
    await join('bob');
    const d = db('bob');
    await assertSucceeds(
      writeBatch(d)
        .update(doc(d, 'trips', TRIP, 'members', 'g1'), { uid: 'bob' })
        .delete(doc(d, 'trips', TRIP, 'members', 'bob'))
        .commit(),
    );
  });

  test('nobody can take over a member already linked to someone else', async () => {
    await createTrip('alice');
    await createInvite('alice');
    await join('bob');
    await assertFails(updateDoc(doc(db('bob'), 'trips', TRIP, 'members', 'alice'), { uid: 'bob' }));
    await assertFails(updateDoc(doc(db('bob'), 'trips', TRIP, 'members', 'alice'), { uid: null }));
  });

  test('renaming the trip also renames the invite', async () => {
    await createTrip('alice');
    await createInvite('alice');
    const d = db('alice');
    await assertSucceeds(
      writeBatch(d)
        .update(doc(d, 'trips', TRIP), { name: '오사카 여행' })
        .update(doc(d, 'invites', CODE), { tripName: '오사카 여행' })
        .commit(),
    );
    await assertFails(updateDoc(doc(d, 'invites', CODE), { tripId: 'other' }));
  });
});

describe('leaving and deleting', () => {
  async function tripWithBob() {
    await createTrip('alice');
    await createInvite('alice');
    await join('bob');
  }

  function leave(uid) {
    const d = db(uid);
    return writeBatch(d)
      .update(doc(d, 'trips', TRIP, 'members', uid), { uid: null })
      .update(doc(d, 'trips', TRIP), { memberUids: arrayRemove(uid) })
      .commit();
  }

  test('a member leaves and stays behind as a name-only companion', async () => {
    await tripWithBob();
    await assertSucceeds(leave('bob'));
    await assertFails(getDoc(doc(db('bob'), 'trips', TRIP)));
    const left = await getDoc(doc(db('alice'), 'trips', TRIP, 'members', 'bob'));
    if (left.data().uid !== null) throw new Error('expected the member to become a guest');
  });

  test('the owner cannot leave, and nobody removes another app user', async () => {
    await tripWithBob();
    await assertFails(leave('alice'));
    await assertFails(updateDoc(doc(db('bob'), 'trips', TRIP), { memberUids: arrayRemove('alice') }));
    await assertFails(updateDoc(doc(db('alice'), 'trips', TRIP), { memberUids: arrayRemove('bob') }));
  });

  test('someone who left can come back with the code and gets their member back', async () => {
    await tripWithBob();
    await leave('bob');
    await assertSucceeds(join('bob'));
  });

  test('only the owner deletes the trip with its members, expenses and invite', async () => {
    await tripWithBob();
    await addGuest('alice', 'g1', '민수');
    const a = db('alice');
    await setDoc(doc(a, 'trips', TRIP, 'expenses', 'e1'), {
      title: '라멘',
      totalMinor: 1800,
      payerId: 'alice',
      createdBy: 'alice',
    });

    const b = db('bob');
    await assertFails(writeBatch(b).delete(doc(b, 'trips', TRIP, 'members', 'alice')).commit());
    await assertFails(writeBatch(b).delete(doc(b, 'trips', TRIP)).commit());

    const batch = writeBatch(a);
    for (const id of ['alice', 'bob', 'g1']) batch.delete(doc(a, 'trips', TRIP, 'members', id));
    batch.delete(doc(a, 'trips', TRIP, 'expenses', 'e1'));
    batch.delete(doc(a, 'invites', CODE));
    await assertSucceeds(batch.commit());
    await assertSucceeds(writeBatch(a).delete(doc(a, 'trips', TRIP)).commit());
  });
});

describe('expenses', () => {
  const expense = (payerId) => ({
    title: '라멘',
    totalMinor: 1800,
    currency: 'JPY',
    payerId,
    createdBy: 'alice',
  });

  test('the payer can be any member, including a name-only companion', async () => {
    await createTrip('alice');
    await addGuest('alice', 'g1', '민수');
    await assertSucceeds(setDoc(doc(db('alice'), 'trips', TRIP, 'expenses', 'e1'), expense('g1')));
    await assertSucceeds(
      updateDoc(doc(db('alice'), 'trips', TRIP, 'expenses', 'e1'), { payerId: 'alice' }),
    );
  });

  test('the payer must be a member of the trip', async () => {
    await createTrip('alice');
    await assertFails(setDoc(doc(db('alice'), 'trips', TRIP, 'expenses', 'e1'), expense('nobody')));
  });

  test('outsiders cannot read or write expenses', async () => {
    await createTrip('alice');
    await assertFails(getDocs(collection(db('bob'), 'trips', TRIP, 'expenses')));
    await assertFails(
      setDoc(doc(db('bob'), 'trips', TRIP, 'expenses', 'e1'), { ...expense('alice'), createdBy: 'bob' }),
    );
  });
});

describe('exchange rates', () => {
  test('signed-in users read rates, nobody writes them from the app', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'rates', '2026-10-23'), { effectiveDate: '2026-10-23', krwPer: { USD: 1385.5 } }),
    );
    await assertSucceeds(getDoc(doc(db('alice'), 'rates', '2026-10-23')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'rates', '2026-10-23')));
    await assertFails(setDoc(doc(db('alice'), 'rates', '2026-10-24'), { krwPer: { USD: 1 } }));
  });

  test('members set a trip rate for currencies without an official one', async () => {
    await createTrip('alice');
    const d = db('alice');
    await assertSucceeds(updateDoc(doc(d, 'trips', TRIP), { 'manualRates.VND': 0.0543 }));
    await assertFails(updateDoc(doc(db('bob'), 'trips', TRIP), { 'manualRates.VND': 1 }));
  });

  test('an expense rate is optional but must be positive', async () => {
    await createTrip('alice');
    const d = db('alice');
    const expense = { title: '쌀국수', totalMinor: 65000, payerId: 'alice', createdBy: 'alice' };
    await assertSucceeds(setDoc(doc(d, 'trips', TRIP, 'expenses', 'e1'), expense));
    await assertSucceeds(
      updateDoc(doc(d, 'trips', TRIP, 'expenses', 'e1'), { krwRate: 0.0543, rateSource: 'manual', rateDate: null }),
    );
    await assertFails(updateDoc(doc(d, 'trips', TRIP, 'expenses', 'e1'), { krwRate: 0 }));
    await assertFails(updateDoc(doc(d, 'trips', TRIP, 'expenses', 'e1'), { krwRate: '54' }));
  });
});

describe('trips from 1.0.0+3', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = ctx.firestore();
      await setDoc(doc(d, 'trips', TRIP), { name: '내 여행', ownerId: 'alice', memberIds: ['alice'] });
      await setDoc(doc(d, 'trips', TRIP, 'expenses', 'e1'), {
        title: '라멘',
        totalMinor: 1800,
        payerId: 'alice',
        createdBy: 'alice',
      });
    });
  });

  test('the owner finds the old trip and moves it to the new structure', async () => {
    const d = db('alice');
    const found = await assertSucceeds(
      getDocs(query(collection(d, 'trips'), where('memberIds', 'array-contains', 'alice'))),
    );
    if (found.size !== 1) throw new Error(`expected 1 legacy trip, got ${found.size}`);
    await assertSucceeds(
      writeBatch(d)
        .update(doc(d, 'trips', TRIP), { memberUids: ['alice'], memberIds: deleteField() })
        .set(doc(d, 'trips', TRIP, 'members', 'alice'), member('나', 'alice', 'alice'))
        .commit(),
    );
    // 옛 지출의 payerId(uid)가 내 멤버 id와 같아서 그대로 고칠 수 있다.
    await assertSucceeds(updateDoc(doc(d, 'trips', TRIP, 'expenses', 'e1'), { title: '돈코츠 라멘' }));
  });

  test('nobody else can claim an old trip', async () => {
    const d = db('bob');
    await assertFails(
      updateDoc(doc(d, 'trips', TRIP), { memberUids: ['bob'], memberIds: deleteField() }),
    );
  });
});
