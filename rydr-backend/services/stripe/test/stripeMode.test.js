const { test } = require("node:test");
const assert = require("node:assert/strict");
const Stripe = require("stripe");
const {
  runtimeConfig,
  modeProfile,
  profilePatch,
  verifyWebhook,
  canChargeRide,
  StripeModeState,
} = require("../stripeMode");
const keys = {
  STRIPE_SECRET_KEY: "sk_test_sample",
  STRIPE_PUBLISHABLE_KEY: "pk_test_sample",
  STRIPE_WEBHOOK_SECRET: "whsec_test_platform",
  STRIPE_DRIVER_VERIFICATION_FLOW_ID: "vf_test_driver",
};
test("preloaded live webhook secrets authenticate inactive events without activating live", () => {
  const config = runtimeConfig({ ...keys, STRIPE_CONNECT_WEBHOOK_SECRET_TEST: "whsec_test", STRIPE_CONNECT_WEBHOOK_SECRET_LIVE: "whsec_live" });
  assert.equal(config.mode, "test");
  assert.equal(config.livePreparation.configured, false);
  const stripe = new Stripe("sk_test_sample");
  const body = JSON.stringify({ id: "evt_live", account: "acct_live", livemode: true, api_version: "2025-05-28.basil" });
  const header = stripe.webhooks.generateTestHeaderString({ payload: body, secret: "whsec_live" });
  assert.equal(verifyWebhook(stripe, body, header, config.connectSecrets, "connect", "test").active, false);
  const unsupported = JSON.stringify({ account: "acct_live", livemode: true, api_version: "future" });
  const unsupportedHeader = stripe.webhooks.generateTestHeaderString({ payload: unsupported, secret: "whsec_live" });
  assert.throws(() => verifyWebhook(stripe, unsupported, unsupportedHeader, config.connectSecrets, "connect", "test"), /version_unsupported/);
});
test("mode is derived from the private key and a mismatched public key fails closed", () => {
  assert.equal(runtimeConfig(keys).mode, "test");
  assert.throws(
    () => runtimeConfig({ ...keys, STRIPE_PUBLISHABLE_KEY: "pk_live_sample" }),
    /stripe_key_mode_mismatch/,
  );
  assert.throws(() => runtimeConfig({ ...keys, STRIPE_SECRET_KEY: "unknown" }));
});
test("live activation requires explicitly scoped webhooks and identity flows", () => {
  const live = {
    ...keys,
    STRIPE_SECRET_KEY: "sk_live_sample",
    STRIPE_PUBLISHABLE_KEY: "pk_live_sample",
  };
  assert.throws(
    () => runtimeConfig(live),
    /live_stripe_configuration_incomplete/,
  );
  const c = runtimeConfig({
    ...live,
    STRIPE_WEBHOOK_SECRET_LIVE: "whsec_live_platform",
    STRIPE_CONNECT_WEBHOOK_SECRET_LIVE: "whsec_live_connect",
    STRIPE_DRIVER_VERIFICATION_FLOW_ID_LIVE: "vf_live_driver",
    STRIPE_RIDER_VERIFICATION_FLOW_ID_LIVE: "vf_live_rider",
  });
  assert.equal(c.platformWebhookSecret, "whsec_live_platform");
  assert.equal(c.identityFlows.driver, "vf_live_driver");
});
test("a draining server cannot switch the shared mode back", async () => {
  let record = { mode: "test", status: "ready", version: 1 };
  let writes = 0;
  const ref = {
    get: async () => ({ data: () => record }),
    set: async () => {
      writes++;
    },
  };
  const state = new StripeModeState({
    mode: "test",
    getDb: () => ({ collection: () => ({ doc: () => ref }) }),
    fieldValue: { serverTimestamp: () => 0 },
  });
  await state.ensure();
  record = { mode: "live", status: "ready", version: 1 };
  await assert.rejects(state.ensure(), /stripe_mode_inactive/);
  assert.equal(writes, 0);
  assert.equal(record.mode, "live");
});
test("test profiles survive live activation without granting test verification or IDs", () => {
  const raw = {
    name: "Driver",
    stripeAccountId: "acct_test",
    identityVerified: true,
    payoutsStepCompleted: true,
    stripeCustomerId: "cus_test",
  };
  const live = profilePatch(raw, {}, "live");
  assert.equal(live.stripeAccountId, null);
  assert.equal(live.identityVerified, false);
  assert.equal(live.payoutsStepCompleted, false);
  assert.equal(live.stripeProfiles.test.stripeAccountId, "acct_test");
  const written = { ...raw, ...live };
  const next = profilePatch(written, { stripeAccountId: "acct_live" }, "live");
  assert.equal(next.stripeProfiles.test.stripeAccountId, "acct_test");
  assert.equal(
    modeProfile({ ...written, ...next }, "live").stripeAccountId,
    "acct_live",
  );
  assert.equal(
    modeProfile({ ...written, ...next }, "test").stripeAccountId,
    "acct_test",
  );
});
test("untagged saved IDs are only inherited in test mode", () => {
  assert.equal(
    modeProfile({ stripeCustomerId: "cus_legacy" }, "test").stripeCustomerId,
    "cus_legacy",
  );
  assert.equal(
    modeProfile({ stripeCustomerId: "cus_legacy" }, "live").stripeCustomerId,
    null,
  );
  assert.equal(
    modeProfile({ stripeMode: "live", stripeAccountId: "acct_live" }, "test")
      .stripeAccountId,
    null,
  );
});
test("verified webhook signatures are scoped and inactive modes never dispatch", () => {
  const stripe = new Stripe("sk_test_sample");
  const body = JSON.stringify({
    id: "evt_test",
    object: "event",
    type: "payout.paid",
    account: "acct_test",
    livemode: false,
  });
  const header = stripe.webhooks.generateTestHeaderString({
    payload: body,
    secret: "whsec_connect",
  });
  assert.equal(
    verifyWebhook(stripe, body, header, "whsec_connect", "connect", "test")
      .active,
    true,
  );
  assert.equal(
    verifyWebhook(stripe, body, header, "whsec_connect", "connect", "live")
      .active,
    false,
  );
  assert.throws(() =>
    verifyWebhook(stripe, body, header, "whsec_platform", "connect", "test"),
  );
  assert.throws(
    () =>
      verifyWebhook(stripe, body, header, "whsec_connect", "platform", "test"),
    /scope_mismatch/,
  );
});
test("live cutover cannot charge an earlier untagged test ride", () => {
  assert.equal(canChargeRide({ stripeMode: "test" }, "live", 100), false);
  assert.equal(
    canChargeRide({ createdAt: { toMillis: () => 99 } }, "live", 100),
    false,
  );
  assert.equal(canChargeRide({}, "live", 100), false);
  assert.equal(
    canChargeRide({ createdAt: { toMillis: () => 101 } }, "live", 100),
    true,
  );
  assert.equal(canChargeRide({}, "test", 100), true);
});
test("activation migrates existing users, marks ready, and is repeatable", async () => {
  const records = new Map([
    ["drivers/d", { stripeAccountId: "acct_test", identityVerified: true }],
    ["riders/r", { stripeCustomerId: "cus_test", verifiedRider: true }],
  ]);
  let time = 100;
  const ref = (path) => ({
    id: path.split("/").at(-1),
    get: async () => ({ data: () => records.get(path) }),
    set: async (d) => records.set(path, { ...records.get(path), ...d }),
    path,
  });
  const db = {
    collection: (c) => ({
      doc: (id) => ref(`${c}/${id}`),
      orderBy: () => ({
        limit: () => ({
          get: async () => {
            const docs = [...records.keys()]
              .filter((k) => k.startsWith(c + "/"))
              .map((k) => ({ id: k.split("/").at(-1), ref: ref(k) }));
            return { docs, size: docs.length };
          },
        }),
      }),
    }),
    runTransaction: async (fn) =>
      fn({ get: (r) => r.get(), set: (r, d) => r.set(d) }),
  };
  const state = new StripeModeState({
    mode: "live",
    getDb: () => db,
    fieldValue: {
      serverTimestamp: () => {
        const captured = time;
        return { toMillis: () => captured };
      },
    },
  });
  await state.ensure();
  assert.equal(records.get("drivers/d").stripeAccountId, null);
  assert.equal(
    records.get("drivers/d").stripeProfiles.test.stripeAccountId,
    "acct_test",
  );
  assert.equal(records.get("riders/r").verifiedRider, false);
  assert.equal(
    records.get("publicDriverProfiles/d").stripeChargesEnabled,
    false,
  );
  assert.equal(records.get("platformConfig/stripeRuntime").status, "ready");
  time = 200;
  await state.ensure();
  assert.equal(
    records.get("platformConfig/stripeRuntime").activatedAt.toMillis(),
    100,
  );
});
