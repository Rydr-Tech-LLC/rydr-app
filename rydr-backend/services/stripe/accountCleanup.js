"use strict";
function blocked(message) { const error = new Error(message); error.statusCode = 409; return error; }
async function cleanupAccount({ stripe, role, uid, requestId, stripeCustomerId, stripeAccountId, mode }) {
  if (!uid || !['rider', 'driver'].includes(role)) throw blocked('A valid account and role are required for cleanup.');
  let account;
  if (stripeAccountId) {
    try { account = await stripe.accounts.retrieve(stripeAccountId); }
    catch (error) { if (error.code !== 'resource_missing') throw error; }
    if (account && !account.deleted && mode === 'live') {
      const balance = await stripe.balance.retrieve({}, { stripeAccount: stripeAccountId });
      if ([...(balance.available || []), ...(balance.pending || []), ...(balance.connect_reserved || [])].some(item => item.amount !== 0)) {
        throw blocked('Settle the connected account balance before deleting this driver.');
      }
      const payouts = await stripe.payouts.list({ limit: 100 }, { stripeAccount: stripeAccountId });
      if (payouts.data.some(payout => ['pending', 'in_transit'].includes(payout.status))) {
        throw blocked('Wait for pending driver payouts to finish before deletion.');
      }
    }
  }
  const result = { role, customer: 'skipped', connectAccount: 'skipped' };
  // Ordinary account closure is never a fraud report or a capabilities downgrade.
  // Stripe rejects unsupported live account closures; let Mission Control surface that error.
  if (stripeAccountId) {
    if (!account || account.deleted) result.connectAccount = 'already_removed';
    else {
      await stripe.accounts.del(stripeAccountId, { idempotencyKey: `account_deletion_connect_${uid}_${requestId}` });
      result.connectAccount = 'deleted';
    }
  }
  if (stripeCustomerId) {
    try {
      await stripe.customers.del(stripeCustomerId, { idempotencyKey: `account_deletion_customer_${uid}_${requestId}` });
      result.customer = 'deleted';
    } catch (error) { if (error.code !== 'resource_missing') throw error; result.customer = 'already_deleted'; }
  }
  return result;
}
module.exports = { cleanupAccount };
