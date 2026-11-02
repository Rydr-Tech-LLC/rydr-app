const test = require('node:test');
const assert = require('node:assert/strict');
const { paymentResolution, reconcileFinancialEvent } = require('../ridePaymentReconciliation');
function fixture() {
  const records = new Map([
    ['rides/ride1', { riderId: 'rider1', driverId: 'driver1', stripeMode: 'test', paymentStatus: 'succeeded', stripePaymentIntentId: 'pi1', netDriverTransferCents: 1800 }],
    ['rides/ride1/financial/outcome', { status: 'paid', paymentIntentId: 'pi1', finalRiderChargeCents: 2000 }]
  ]);
  const ref = path => ({ id: path.split('/').at(-1), path, get: async () => ({ exists: records.has(path), data: () => records.get(path) }), collection: name => collection(`${path}/${name}`) });
  const collection = path => ({ doc: id => ref(`${path}/${id}`) });
  const db = { collection, runTransaction: async fn => {
    const writes = []; const result = await fn({ get: r => r.get(), set: (r, value) => writes.push([r.path, value]) });
    for (const [path, value] of writes) records.set(path, { ...records.get(path), ...value }); return result;
  } };
  const intent = { id: 'pi1', metadata: { rideId: 'ride1', riderId: 'rider1' }, amount_received: 2000, currency: 'usd', livemode: false };
  const charge = { id: 'ch1', payment_intent: 'pi1', amount_refunded: 2000 };
  const dispute = { id: 'dp1', payment_intent: 'pi1', amount: 2000, status: 'needs_response' };
  const stripe = { paymentIntents: { retrieve: async () => intent }, charges: { retrieve: async () => charge }, disputes: { retrieve: async () => dispute } };
  return { records, charge, intent, dispute, input: { stripe, db, mode: 'test', fieldValue: { serverTimestamp: () => 1 } } };
}
test('manually resolved and refunded balances cannot be charged by stale payment jobs', () => {
  for (const status of ['written_off', 'paid_externally', 'refunded']) assert.equal(paymentResolution({ paymentStatus: status }).status, 'resolved');
  assert.equal(paymentResolution({ paymentStatus: 'failed' }), null);
});
test('full refunds reconcile receipts and create one driver-transfer review without moving money', async () => {
  const f = fixture();
  await reconcileFinancialEvent({ ...f.input, type: 'charge.refunded', objectId: 'ch1' });
  await reconcileFinancialEvent({ ...f.input, type: 'charge.refunded', objectId: 'ch1' });
  assert.equal(f.records.get('rides/ride1').paymentStatus, 'refunded');
  assert.equal(f.records.get('rides/ride1/financial/outcome').status, 'paid');
  assert.equal(f.records.get('rides/ride1/financial/outcome').refundedAmountCents, 2000);
  assert.equal(f.records.get('financialReviewCases/refund_ch1').driverTransferReviewRequired, true);
  assert.equal([...f.records.keys()].filter(k => k.startsWith('financialReviewCases/')).length, 1);
});
test('partial refunds preserve the paid fare and store the actual refunded amount', async () => {
  const f = fixture(); f.charge.amount_refunded = 500;
  await reconcileFinancialEvent({ ...f.input, type: 'charge.refunded', objectId: 'ch1' });
  assert.equal(f.records.get('rides/ride1').paymentStatus, 'succeeded');
  assert.equal(f.records.get('rides/ride1').refundStatus, 'partially_refunded');
});
test('replaying a refund does not reopen a completed financial review', async () => {
  const f = fixture(); await reconcileFinancialEvent({ ...f.input, type: 'charge.refunded', objectId: 'ch1' });
  f.records.get('financialReviewCases/refund_ch1').status = 'resolved';
  await reconcileFinancialEvent({ ...f.input, type: 'charge.refunded', objectId: 'ch1' });
  assert.equal(f.records.get('financialReviewCases/refund_ch1').status, 'resolved');
});
test('events for another intent, owner, or payment mode cannot modify a ride', async () => {
  for (const change of [f => f.intent.id = 'pi_other', f => f.intent.metadata.riderId = 'other', f => f.intent.livemode = true]) {
    const f = fixture(); change(f);
    assert.equal((await reconcileFinancialEvent({ ...f.input, type: 'charge.refunded', objectId: 'ch1' })).ignored, true);
    assert.equal(f.records.get('rides/ride1').paymentStatus, 'succeeded');
  }
});
test('out-of-order dispute events use current Stripe status and resolve a won dispute', async () => {
  const f = fixture();
  await reconcileFinancialEvent({ ...f.input, type: 'charge.dispute.created', objectId: 'dp1' });
  assert.equal(f.records.get('financialReviewCases/dispute_dp1').status, 'open');
  f.dispute.status = 'won';
  await reconcileFinancialEvent({ ...f.input, type: 'charge.dispute.created', objectId: 'dp1' });
  assert.equal(f.records.get('rides/ride1').disputeStatus, 'won');
  assert.equal(f.records.get('financialReviewCases/dispute_dp1').status, 'resolved');
});

test('support resolution wins a race with a settlement attempt before any capture is claimed', async () => {
  const { claimRideSettlement } = require('../ridePaymentReconciliation');
  const f = fixture(); f.records.get('rides/ride1').paymentStatus = 'written_off';
  const rideRef = f.input.db.collection('rides').doc('ride1');
  const settlementRef = rideRef.collection('financial').doc('settlement');
  const result = await claimRideSettlement({ db: f.input.db, rideRef, settlementRef, plan: { amountCents: 2000 }, fieldValue: f.input.fieldValue });
  assert.equal(result.resolution.resolutionType, 'written_off');
  assert.equal(f.records.has('rides/ride1/financial/settlement'), false);
  assert.equal(f.records.get('rides/ride1').paymentStatus, 'written_off');
});
