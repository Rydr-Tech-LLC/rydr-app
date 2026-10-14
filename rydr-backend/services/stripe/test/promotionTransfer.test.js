const { test } = require("node:test");
const assert = require("node:assert/strict");
const { promotionTransfer } = require("../promotionTransfer");
function setup() {
  let saved,
    calls = 0;
  const ref = { update: async (d) => (saved = { ...saved, ...d }) };
  const db = {
    runTransaction: async (fn) =>
      fn({
        get: async () => ({ data: () => saved }),
        create: (_, d) => (saved = d),
      }),
  };
  const stripe = {
    transfers: {
      create: async () => {
        calls++;
        return { id: "tr_1" };
      },
    },
  };
  const options = {
    db,
    ref,
    stripe,
    fieldValue: { serverTimestamp: () => new Date() },
    amount: 1000,
    destination: "acct_1",
    metadata: { rideId: "ride" },
    idempotencyKey: "promo_subsidy_ride",
    mode: "test",
  };
  return { options, read: () => saved, calls: () => calls };
}
test("full fare funding is dispatched once and repeated callbacks reuse the recorded transfer", async () => {
  const s = setup();
  assert.equal(
    (await promotionTransfer(s.options)).transferStatus,
    "succeeded",
  );
  assert.equal((await promotionTransfer(s.options)).transferId, "tr_1");
  assert.equal(s.calls(), 1);
});
test("uncertain transfer outcome is flagged, never automatically resubmitted", async () => {
  const s = setup();
  s.options.stripe.transfers.create = async () => {
    throw Error("Connection lost");
  };
  assert.equal(
    (await promotionTransfer(s.options)).transferStatus,
    "needs_review",
  );
  assert.equal(
    (await promotionTransfer(s.options)).transferStatus,
    "needs_review",
  );
  assert.equal(s.read().status, "needs_review");
});
test("changed destination or mode cannot reuse or send an existing funding transfer", async () => {
  const s = setup();
  await promotionTransfer(s.options);
  assert.equal(
    (await promotionTransfer({ ...s.options, destination: "acct_other" }))
      .transferStatus,
    "needs_review",
  );
  assert.equal(
    (await promotionTransfer({ ...s.options, mode: "live" })).transferStatus,
    "needs_review",
  );
  assert.equal(s.calls(), 1);
});
