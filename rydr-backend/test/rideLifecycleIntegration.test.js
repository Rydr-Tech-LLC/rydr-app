const test = require('node:test');
const assert = require('node:assert/strict');
const firebase = require('../src/config/firebase');
let currentDb;
firebase.getFirestore = () => currentDb;
const { transitionRide } = require('../src/services/rideLifecycleService');
const { setDriverRequestPreference } = require('../src/services/driverPresenceService');
const { promoteNextQueuedRide } = require('../src/services/driverQueueService');
const stamp = ms => firebase.admin.firestore.Timestamp.fromMillis(ms);
class Ref {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split('/').at(-1); }
  collection(name) { return new Query(this.db, `${this.path}/${name}`); }
  async get() { const value = this.db.values.get(this.path); return { exists: value != null, data: () => value, id: this.id, ref: this }; }
}
class Query {
  constructor(db, path, filters = []) { Object.assign(this, { db, path, filters }); }
  doc(id) { return new Ref(this.db, `${this.path}/${id}`); }
  where(field, op, value) { return new Query(this.db, this.path, [...this.filters, [field, op, value]]); }
  limit() { return this; }
  async get() {
    const docs = [];
    for (const [path, value] of this.db.values) {
      if (path.split('/').length !== this.path.split('/').length + 1 || !path.startsWith(`${this.path}/`)) continue;
      if (this.filters.every(([f, op, v]) => op === 'in' ? v.includes(value[f]) : value[f] === v)) docs.push(await new Ref(this.db, path).get());
    }
    return { docs, empty: docs.length === 0 };
  }
}
class Db {
  constructor(values) { this.values = new Map(Object.entries(values)); this.tail = Promise.resolve(); }
  collection(name) { return new Query(this, name); }
  async runTransaction(callback) {
    const previous = this.tail; let unlock;
    this.tail = new Promise(resolve => { unlock = resolve; });
    await previous;
    try {
      const writes = [];
      const tx = { get: ref => ref.get(), set: (ref, value, options) => writes.push([ref, value, options]),
        create: (ref, value) => { if (this.values.has(ref.path)) throw new Error('already_exists'); writes.push([ref, value]); } };
      const result = await callback(tx);
      for (const [ref, value, options] of writes) this.values.set(ref.path, { ...(options?.merge ? this.values.get(ref.path) : {}), ...value });
      return result;
    } finally { unlock(); }
  }
}
function fixture() {
  const now = Date.now();
  const request = { riderId: 'rider1', driverId: 'driver1', rideType: 'go', status: 'pending', dispatchStatus: 'offered',
    authorizationPolicy: 'estimate_hold_v1', authorizationStatus: 'authorized', offerExpiresAt: stamp(now + 60000),
    driverMinimumFareCents: 700, driverRatePerMileCents: 100, driverRatePerMinuteCents: 25,
    backendRouteProvider: 'apple_maps', backendDistanceMeters: 1000, backendDurationSeconds: 300,
    backendDistanceMiles: 0.62, backendDurationMinutes: 5 };
  currentDb = new Db({ 'drivers/driver1': { isApproved: true, driverSignupCompleted: true, tierRates: { go: { minimumFare: 99, perMile: 99, perMinute: 99 } } },
    'driver_status/driver1': { isOnline: true, availabilityStatus: 'available', presenceExpiresAt: stamp(now + 60000) },
    'rideRequests/ride1': { ...request }, 'rideRequests/ride2': { ...request, riderId: 'rider2' }, 'rideRequests/ride3': { ...request, riderId: 'rider3' } });
  return currentDb;
}
const accept = (rideId, requestId) => transitionRide({ rideId, uid: 'driver1', action: 'driver_accept', requestId, queued: false });
test('simultaneous accepts create one active ride and one queued ride regardless of client flags', async () => {
  const db = fixture();
  await Promise.all([accept('ride1', 'request-0001'), accept('ride2', 'request-0002')]);
  const rides = [db.values.get('rides/ride1'), db.values.get('rides/ride2')];
  assert.equal(rides.filter(r => r.driverQueueStatus === 'active').length, 1);
  assert.equal(rides.filter(r => r.driverQueueStatus === 'queued').length, 1);
  await assert.rejects(accept('ride3', 'request-0003'), /already has a queued ride/);
});
test('stopping requests blocks an already delivered offer at the backend', async () => {
  fixture();
  await setDriverRequestPreference({ uid: 'driver1', stopRequestsAfterRide: true });
  await assert.rejects(accept('ride1', 'request-0001'), /not accepting requests/);
});
test('acceptance preserves the quote instead of replacing it with current driver rates', async () => {
  const db = fixture(); await accept('ride1', 'request-0001');
  assert.equal(db.values.get('rides/ride1').driverRatePerMileCents, 100);
  assert.equal(db.values.get('rides/ride1').driverMinimumFareCents, 700);
});
test('new dispatch requires authorization even if an offer was published incorrectly', async () => {
  const db = fixture(); db.values.get('rideRequests/ride1').authorizationStatus = 'failed';
  await assert.rejects(accept('ride1', 'request-0001'), /authorization is required/);
});
test('server rejects arrival without a recent location near pickup', async () => {
  const db = fixture(); await accept('ride1', 'request-0001');
  await assert.rejects(transitionRide({ rideId: 'ride1', uid: 'driver1', action: 'arrive_pickup', requestId: 'arrive-0001' }), /recent driver location/);
  Object.assign(db.values.get('rides/ride1'), { driverLocation: { lat: 33.75, lng: -84.39, updatedAt: stamp(Date.now()) }, pickupCoordinate: { lat: 33.75, lng: -84.39 } });
  await transitionRide({ rideId: 'ride1', uid: 'driver1', action: 'arrive_pickup', requestId: 'arrive-0002' });
  const ride = db.values.get('rides/ride1');
  assert.equal(ride.pickupPaidWaitStartedAt.toMillis() - ride.arrivedAtPickupAt.toMillis(), 180000);
});
test('paid waiting cannot begin early or reset after another request ID', async () => {
  const db = fixture(); const now = Date.now();
  db.values.set('rides/ride1', { ...db.values.get('rideRequests/ride1'), status: 'arrivedAtPickup', arrivedAtPickupAt: stamp(now) });
  await assert.rejects(transitionRide({ rideId: 'ride1', uid: 'driver1', action: 'start_paid_wait', requestId: 'waiting-0001' }), /has not ended/);
  Object.assign(db.values.get('rides/ride1'), { arrivedAtPickupAt: stamp(now - 600000), pickupPaidWaitStartedAt: stamp(now - 420000) });
  await transitionRide({ rideId: 'ride1', uid: 'driver1', action: 'start_paid_wait', requestId: 'waiting-0002' });
  await transitionRide({ rideId: 'ride1', uid: 'driver1', action: 'start_paid_wait', requestId: 'waiting-0003' });
  assert.equal(db.values.get('rides/ride1').pickupPaidWaitStartedAt.toMillis(), now - 420000);
});
test('an accepted queued ride can be promoted after stopping new requests', async () => {
  const db = fixture(); await accept('ride1', 'request-0001'); await accept('ride2', 'request-0002');
  db.values.get('rides/ride1').status = 'completed';
  await setDriverRequestPreference({ uid: 'driver1', stopRequestsAfterRide: true });
  const result = await promoteNextQueuedRide({ driverId: 'driver1', requestId: 'promote-0001', db });
  assert.equal(result.rideId, 'ride2');
  assert.equal(db.values.get('rides/ride2').driverQueueStatus, 'active');
});
