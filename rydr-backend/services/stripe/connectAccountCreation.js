"use strict";
const { FieldValue } = require("firebase-admin/firestore");
function definiteRestriction(error) {
  return error?.type === "StripeInvalidRequestError" && error.statusCode === 400
    && /temporarily restricted your ability to create[\s\S]*connected account/i.test(String(error?.raw?.message || error?.message || ""));
}
function replayed(error) {
  return String(error?.headers?.["idempotent-replayed"] || error?.raw?.headers?.["idempotent-replayed"]).toLowerCase() === "true";
}
function generation(data) {
  const value = data?.generation ?? 0;
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("Invalid Connect setup attempt state");
  return value;
}
async function storedAccount(stripe, id) {
  const account = await stripe.accounts.retrieve(id);
  if (account.deleted) throw new Error("Stored Connect setup account has been deleted; support review required");
  return account;
}
async function createConnectAccount({ stripe, db, uid, params }) {
  const ref = db.collection("stripeConnectSetupAttempts").doc(uid);
  const state = (await ref.get()).data();
  if (state?.accountId) return storedAccount(stripe, state.accountId);
  let attempt = generation(state);
  for (let retry = 0; ; retry += 1) {
    try {
      // Preserve the legacy key for uncertain requests. A new generation is
      // permitted only after Stripe explicitly confirms a rejected creation.
      const suffix = attempt === 0 ? "" : `_retry${attempt}`;
      const account = await stripe.accounts.create(params, { idempotencyKey: `connect_account_create_${uid}${suffix}` });
      await ref.set({ accountId: account.id, status: "created", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return account;
    } catch (error) {
      if (!definiteRestriction(error)) throw error;
      const next = await db.runTransaction(async transaction => {
        const current = (await transaction.get(ref)).data();
        if (current?.accountId) return { accountId: current.accountId };
        const actual = generation(current);
        if (actual === attempt) {
          transaction.set(ref, { generation: actual + 1, status: "restricted", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
          return { generation: actual + 1 };
        }
        return { generation: actual };
      });
      if (next.accountId) return storedAccount(stripe, next.accountId);
      attempt = next.generation;
      // One immediate recovery is allowed for a cached rejection. Fresh
      // restrictions stay blocked, and ambiguous errors retain their key.
      if (!replayed(error) || retry >= 1) throw error;
    }
  }
}
module.exports = { createConnectAccount, definiteRestriction, replayed };
