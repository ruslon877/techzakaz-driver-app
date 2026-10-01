import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp({ projectId: 'techzakaz-e273a' });
const db = getFirestore();

const nearToken = 'emulator-token-near';
const farToken = 'emulator-token-far';

await db.collection('drivers').doc('near-driver').set({
  fcmToken: nearToken,
  isOnline: true,
  lat: 43.238949,
  lon: 76.889709,
});
await db.collection('drivers').doc('far-driver').set({
  fcmToken: farToken,
  isOnline: true,
  lat: 43.35,
  lon: 77.15,
});

const order = await db.collection('orders').add({
  type: 'Эвакуатор',
  status: 'active',
  lat: 43.238949,
  lon: 76.889709,
  address: 'Эмуляторная заявка, Алматы',
});

const deadline = Date.now() + 20_000;
let dispatch = null;
while (Date.now() < deadline) {
  const snapshot = await db.collection('_emulatorDispatches').doc(order.id).get();
  if (snapshot.exists) {
    dispatch = snapshot.data();
    break;
  }
  await new Promise((resolve) => setTimeout(resolve, 500));
}

assert.ok(dispatch, 'Cloud Function did not record a dispatch in time');
assert.deepEqual(dispatch.tokens, [nearToken], 'Only the nearby driver should receive the dispatch');
assert.equal(dispatch.radiusKm, 5);
console.log(JSON.stringify({
  ok: true,
  orderId: order.id,
  recipients: dispatch.tokens,
  radiusKm: dispatch.radiusKm,
}));
