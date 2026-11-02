const test = require('node:test');
const assert = require('node:assert/strict');
const { RideAuthorizationService } = require('../rideAuthorization');
function fixture(overrides = {}) {
  const records = new Map([['rideRequests/ride1', { status: 'authorizing', riderId: 'rider1', estimatedRiderTotalCents: 2000, ...overrides }]]);
  const intents = new Map(); const calls = [];
  const db = { collection: name => ({ where: () => ({ where: () => ({ limit: () => ({ get: async () => ({ empty: true }) }) }) }), doc: id => ({ get: async () => ({ exists: records.has(`${name}/${id}`), data: () => records.get(`${name}/${id}`) }), set: async value => records.set(`${name}/${id}`, { ...records.get(`${name}/${id}`), ...value }) }) }) };
  db.runTransaction = async callback => callback({ get: ref => ref.get(), set: (ref, value) => ref.set(value) });
  const stripe = { customers: { retrieve: async () => ({ invoice_settings: { default_payment_method: 'pm1' } }) }, paymentMethods: { retrieve: async () => ({ customer: "cus1", type: "card" }), list: async () => ({ data: [{ id: 'pm1' }] }) }, paymentIntents: {
    create: async (params, options) => {
      calls.push(['create', params, options]);
      const existing = [...intents.values()].find(i => i.key === options.idempotencyKey);
      if (existing) return existing;
      const pi = { ...params, id: `pi${intents.size + 1}`, key: options.idempotencyKey, status: 'requires_confirmation' }; intents.set(pi.id, pi); return pi;
    },
    retrieve: async id => intents.get(id),
    confirm: async id => { calls.push(['confirm', id]); const pi = intents.get(id); pi.status = 'requires_capture'; pi.amount_capturable = pi.amount; return pi; },
    cancel: async id => { calls.push(['cancel', id]); const pi = intents.get(id); pi.status = 'canceled'; return pi; },
    capture: async (id, params) => { calls.push(['capture', id, params]); const pi = intents.get(id); pi.status = 'succeeded'; pi.amount_received = params.amount_to_capture; return pi; }
  } };
  const service = new RideAuthorizationService({ stripe, mode: 'test', getDb: () => db, customerFor: async () => 'cus1', fieldValue: { serverTimestamp: () => 1 } });
  return { service, records, intents, stripe, calls };
}
test('dispatch authorization reserves exactly the estimate without capturing', async () => {
  const f = fixture(); const result = await f.service.authorize('ride1');
  assert.equal(result.amountCents, 2000); assert.equal(result.status, 'authorized');
  assert.equal(f.calls[0][1].capture_method, 'manual');
  assert.equal(f.calls.filter(c => c[0] === 'capture').length, 0);
});
test('repeated authorization reuses the same hold after a lost response', async () => {
  const f = fixture(); await f.service.authorize('ride1'); await f.service.authorize('ride1');
  assert.equal(f.calls.filter(c => c[0] === 'create').length, 1);
});
test('card authentication blocks dispatch and returns the same intent secret', async () => {
  const f = fixture(); f.stripe.paymentIntents.confirm = async id => Object.assign(f.intents.get(id), { status: 'requires_action', client_secret: 'secret' });
  await assert.rejects(f.service.authorize('ride1'), e => e.code === 'authentication_required' && e.clientSecret === 'secret');
  assert.equal(f.records.get('rideRequests/ride1').authorizationStatus, 'requires_action');
  Object.assign(f.intents.get('pi1'), { status: 'requires_capture', amount_capturable: 2000 });
  assert.equal((await f.service.authorize('ride1')).status, 'authorized');
  assert.equal(f.intents.size, 1);
});
test('decline never marks the estimate authorized', async () => {
  const f = fixture(); f.stripe.paymentIntents.confirm = async id => Object.assign(f.intents.get(id), { status: 'requires_payment_method' });
  await assert.rejects(f.service.authorize('ride1'), e => e.code === 'card_authorization_failed');
  assert.equal(f.records.get('rideRequests/ride1').authorizationStatus, 'failed');
});
test('lower final fare captures only the amount owed and retries do not recapture', async () => {
  const f = fixture(); await f.service.authorize('ride1');
  const input = { rideId: 'ride1', amount: 1500, customerId: 'cus1', paymentMethodId: 'pm1' };
  await f.service.settle(input); await f.service.settle(input);
  assert.equal(f.intents.size, 1); assert.equal(f.calls.filter(c => c[0] === 'capture').length, 1);
  assert.equal(f.intents.get('pi1').amount_received, 1500);
});
test('higher final fare authorizes the final amount before releasing the estimate', async () => {
  const f = fixture(); await f.service.authorize('ride1');
  await f.service.settle({ rideId: 'ride1', amount: 2500, customerId: 'cus1', paymentMethodId: 'pm1' });
  assert.equal(f.intents.get('pi1').status, 'canceled'); assert.equal(f.intents.get('pi2').amount_received, 2500);
  assert.ok(f.calls.findIndex(c => c[0] === 'confirm' && c[1] === 'pi2') < f.calls.findIndex(c => c[0] === 'cancel'));
});
test('declined fare increase preserves the existing estimate hold', async () => {
  const f = fixture(); await f.service.authorize('ride1');
  f.stripe.paymentIntents.confirm = async () => { throw new Error('declined'); };
  await assert.rejects(f.service.settle({ rideId: 'ride1', amount: 2500, customerId: 'cus1', paymentMethodId: 'pm1' }));
  assert.equal(f.intents.get('pi1').status, 'requires_capture');
});
test('cancellation releases an uncaptured hold idempotently', async () => {
  const f = fixture(); await f.service.authorize('ride1'); await f.service.release('ride1'); await f.service.release('ride1');
  assert.equal(f.calls.filter(c => c[0] === 'cancel').length, 1);
});
test('release never cancels a captured payment', async () => {
  const f = fixture(); await f.service.authorize('ride1');
  await f.service.settle({ rideId: 'ride1', amount: 2000, customerId: 'cus1', paymentMethodId: 'pm1' });
  assert.equal((await f.service.release('ride1')).released, false);
});

test('a rider-selected card must belong to that rider before a hold is created', async () => {
  const f = fixture({ requestedPaymentMethodId: 'pm_other' });
  f.stripe.paymentMethods.retrieve = async () => ({ customer: 'cus_other', type: 'card' });
  await assert.rejects(f.service.authorize('ride1'), e => e.code === 'payment_method_not_owned');
  assert.equal(f.intents.size, 0);
});
test('an expired hold is replaced before dispatch and is never treated as authorized', async () => {
  const f = fixture(); await f.service.authorize('ride1');
  f.intents.get('pi1').status = 'canceled';
  await f.service.authorize('ride1');
  assert.equal(f.intents.size, 2); assert.equal(f.intents.get('pi2').status, 'requires_capture');
});

test('a cancellation racing successful authorization schedules release and never republishes the request', async () => {
  const f = fixture();
  f.stripe.paymentIntents.confirm = async id => {
    f.records.get('rideRequests/ride1').status = 'cancelled';
    return Object.assign(f.intents.get(id), { status: 'requires_capture', amount_capturable: 2000 });
  };
  await assert.rejects(f.service.authorize('ride1'), e => e.code === 'ride_request_cancelled');
  assert.equal(f.records.get('rideRequests/ride1').status, 'cancelled');
  assert.equal(f.records.get('authorizationReleaseJobs/ride1_pi1').status, 'pending');
});

test('a delayed authorization response must not release a hold after the driver already accepted', async () => {
  const f = fixture();
  f.stripe.paymentIntents.confirm = async id => {
    Object.assign(f.records.get('rideRequests/ride1'), { status: 'accepted', authorizationStatus: 'authorized' });
    return Object.assign(f.intents.get(id), { status: 'requires_capture', amount_capturable: 2000 });
  };
  assert.equal((await f.service.authorize('ride1')).status, 'authorized');
  assert.equal(f.records.has('authorizationReleaseJobs/ride1_pi1'), false);
});
