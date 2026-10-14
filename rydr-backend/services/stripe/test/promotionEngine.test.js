const { test } = require("node:test");
const assert = require("node:assert/strict");
const { PromotionEngine, key } = require("../promotionEngine");
const now = Date.parse("2026-10-14T15:00:00Z");
function setup() {
  const docs = new Map();
  let queue = Promise.resolve(),
    transfers = [];
  const snapshot = (path) => ({
    exists: docs.has(path),
    id: path.split("/").at(-1),
    ref: ref(path),
    data: () => structuredClone(docs.get(path)),
  });
  function ref(path) {
    return {
      path,
      id: path.split("/").at(-1),
      collection: (n) => collection(`${path}/${n}`),
      get: async () => snapshot(path),
      update: async (d) => docs.set(path, { ...docs.get(path), ...d }),
    };
  }
  function collection(path, filters = []) {
    return {
      doc: (id) => ref(`${path}/${id}`),
      where: (f, op, v) => collection(path, [...filters, [f, op, v]]),
      get: async () => ({
        docs: [...docs.keys()]
          .filter(
            (k) =>
              k.startsWith(path + "/") &&
              k.split("/").length === path.split("/").length + 1 &&
              filters.every(([f, op, v]) =>
                op === "in" ? v.includes(docs.get(k)[f]) : docs.get(k)[f] === v,
              ),
          )
          .map(snapshot),
      }),
    };
  }
  const db = {
    collection,
    runTransaction: (fn) => {
      const run = queue.then(async () => {
        let writes = [],
          written = false;
        const result = await fn({
          get: async (r) => {
            assert.equal(
              written,
              false,
              "Firestore requires reads before writes",
            );
            return snapshot(r.path);
          },
          create: (r, d) => {
            written = true;
            assert.equal(docs.has(r.path), false);
            writes.push(() => docs.set(r.path, d));
          },
          update: (r, d) => {
            written = true;
            writes.push(() => docs.set(r.path, { ...docs.get(r.path), ...d }));
          },
          set: (r, d, o) => {
            written = true;
            writes.push(() =>
              docs.set(r.path, o?.merge ? { ...docs.get(r.path), ...d } : d),
            );
          },
        });
        writes.forEach((w) => w());
        return result;
      });
      queue = run.catch(() => {});
      return run;
    },
  };
  const stripe = {
    accounts: {
      retrieve: async () => ({
        metadata: { uid: "driver" },
        details_submitted: true,
      }),
    },
    transfers: {
      create: async (params, options) => {
        transfers.push({ params, options });
        return { id: "tr_bonus" };
      },
    },
  };
  const engine = new PromotionEngine({
    db,
    fieldValue: { serverTimestamp: () => new Date(now) },
    stripe,
    mode: "test",
    now: () => now,
  });
  const offer = {
    id: "promo",
    schemaVersion: 2,
    title: "Reward",
    status: "active",
    type: "rider_fare_discount",
    audience: "riders",
    appliesTo: "normalRydr",
    startsAt: new Date(now - 86400000),
    endsAt: new Date(now + 86400000),
    applicationMode: "automatic",
    audienceRule: "all",
    discountKind: "fixed",
    discountCents: 500,
    perUserLimit: 1,
    maxRedemptions: 10,
    markets: [],
    rideTypes: [],
    rewardExpiresAfterDays: 30,
  };
  const outcome = {
    status: "finalized",
    outcomeType: "completed",
    grossChargeCents: 2500,
    finalRiderChargeCents: 2500,
    rideSubtotalCents: 2000,
    bookingFeeCents: 500,
    driverPayoutCents: 1600,
    platformShareCents: 900,
  };
  const ride = {
    riderId: "rider",
    driverId: "driver",
    rideType: "Rydr Go",
    status: "completed",
    paymentStatus: "succeeded",
    completedAt: new Date(now - 1000),
  };
  docs.set("promotions/promo", offer);
  function paid(id = "ride", data = ride, financial = outcome) {
    docs.set(`rides/${id}`, data);
    docs.set(`rides/${id}/financial/outcome`, { ...financial, status: "paid" });
  }
  return { engine, docs, stripe, transfers, offer, outcome, ride, paid };
}
test("retry reuses the reserved fare even after promotion is paused", async () => {
  const s = setup();
  const r = await s.engine.reserveRider({
    rideId: "ride",
    ride: s.ride,
    outcome: s.outcome,
    uid: "rider",
  });
  assert.equal(r.discountCents, 500);
  s.docs.get("promotions/promo").status = "paused";
  const again = await s.engine.reserveRider({
    rideId: "ride",
    ride: s.ride,
    outcome: s.outcome,
    uid: "rider",
  });
  assert.equal(again.discountCents, 500);
  assert.equal(s.docs.get("promotionUsage/promo").issuedCount, 1);
});
test("concurrent finalizations respect global caps atomically", async () => {
  const s = setup();
  s.docs.get("promotions/promo").maxRedemptions = 1;
  const results = await Promise.all(
    ["a", "b"].map((uid) =>
      s.engine.reserveRider({
        rideId: uid,
        ride: { ...s.ride, riderId: uid },
        outcome: s.outcome,
        uid,
      }),
    ),
  );
  assert.equal(results.filter(Boolean).length, 1);
  assert.equal(s.docs.get("promotionUsage/promo").issuedCount, 1);
});
test("wrong code, wrong audience and new-user ineligibility never enroll", async () => {
  const s = setup();
  s.docs.get("promotions/promo").applicationMode = "code";
  s.docs.get("promotions/promo").promoCode = "FIRST";
  s.docs.set("promotionCodes/FIRST", { promotionId: "promo" });
  await assert.rejects(s.engine.enroll("rider", "nope"), /not found/);
  await assert.rejects(s.engine.enroll("driver", "FIRST", "drivers"));
  const unavailable = await s.engine.reserveRider({
    rideId: "ride",
    ride: s.ride,
    outcome: s.outcome,
    uid: "rider",
  });
  assert.equal(unavailable, null);
  await s.engine.enroll("rider", "first");
  const enrolled = s.docs.get(`promotionEnrollments/${key("promo", "rider")}`);
  assert.equal(enrolled.promotionId, "promo");
});
test("code enrollment unlocks fare credit and settled reservation records once", async () => {
  const s = setup();
  Object.assign(s.docs.get("promotions/promo"), {
    applicationMode: "code",
    promoCode: "TEST",
  });
  s.docs.set("promotionCodes/TEST", { promotionId: "promo" });
  await s.engine.enroll("rider", "TEST");
  await s.engine.reserveRider({
    rideId: "ride",
    ride: s.ride,
    outcome: s.outcome,
    uid: "rider",
  });
  s.paid();
  await s.engine.settle("ride");
  await s.engine.settle("ride");
  assert.equal(s.docs.get("rides/ride/financial/promotion").status, "applied");
  assert.equal(
    [...s.docs.keys()].filter((x) => x.startsWith("promotionRedemptions/"))
      .length,
    1,
  );
});
test("new rider milestone persists cohort, grants once and earned reward survives campaign end", async () => {
  const s = setup();
  Object.assign(s.docs.get("promotions/promo"), {
    type: "rider_milestone_reward",
    milestoneRideCount: 2,
    rewardKind: "free_ride",
    limitKind: "distance",
    maxDistanceMiles: 10,
    audienceRule: "new",
  });
  s.paid("one", { ...s.ride, completedAt: new Date(now - 2000) });
  await s.engine.settle("one");
  s.paid("two");
  await s.engine.settle("two");
  await s.engine.settle("two");
  const rewards = [...s.docs.entries()].filter(([k]) =>
    k.startsWith("promotionRewards/"),
  );
  assert.equal(rewards.length, 1);
  assert.equal(rewards[0][1].status, "available");
  s.docs.get("promotions/promo").status = "ended";
  const r = await s.engine.reserveRider({
    rideId: "three",
    ride: s.ride,
    outcome: { ...s.outcome, calculationInputs: { billableDistance: 20 } },
    uid: "rider",
  });
  assert.equal(r.discountCents, 1500);
  assert.equal(r.rewardId, rewards[0][0].split("/").at(-1));
});
test("failed and discounted rider rides never advance milestones", async () => {
  const s = setup();
  Object.assign(s.docs.get("promotions/promo"), {
    type: "rider_milestone_reward",
    milestoneRideCount: 1,
    rewardKind: "free_ride",
  });
  s.paid("bad", { ...s.ride, paymentStatus: "failed" });
  await s.engine.settle("bad");
  s.paid("free", s.ride, {
    ...s.outcome,
    promotionDiscountCents: 2500,
    finalRiderChargeCents: 0,
  });
  await s.engine.settle("free");
  assert.equal(
    [...s.docs.keys()].filter((x) => x.startsWith("promotionProgress/")).length,
    0,
  );
});
test("driver bonus adds a separate idempotent transfer, preserving full-fare outcome", async () => {
  const s = setup();
  Object.assign(s.docs.get("promotions/promo"), {
    type: "driver_per_ride_bonus",
    audience: "drivers",
    bonusCents: 200,
  });
  s.docs.set("drivers/driver", {
    stripeAccountId: "acct_test",
    stripeChargesEnabled: true,
    stripeMode: "test",
  });
  s.paid();
  await s.engine.settle("ride");
  await s.engine.settle("ride");
  assert.equal(s.transfers.length, 1);
  assert.equal(s.transfers[0].params.amount, 200);
  assert.match(s.transfers[0].options.idempotencyKey, /promotion-bonus-/);
  assert.equal(
    s.docs.get("rides/ride/financial/outcome").driverPayoutCents,
    1600,
  );
});
test("driver milestone threshold and payout issue are durable and do not resubmit ambiguously", async () => {
  const s = setup();
  Object.assign(s.docs.get("promotions/promo"), {
    type: "driver_milestone_reward",
    audience: "drivers",
    milestoneRideCount: 2,
    rewardKind: "cash_bonus",
    rewardCents: 1000,
  });
  s.docs.set("drivers/driver", {
    stripeAccountId: "acct_test",
    stripeChargesEnabled: true,
  });
  s.stripe.transfers.create = async () => {
    s.transfers.push({});
    throw Error("Connection lost");
  };
  s.paid("one");
  await s.engine.settle("one");
  assert.equal(s.transfers.length, 0);
  s.paid("two");
  await s.engine.settle("two");
  await s.engine.settle("two");
  assert.equal(s.transfers.length, 1);
  assert.equal(
    [...s.docs.entries()].find(([k]) =>
      k.startsWith("promotionRedemptions/"),
    )[1].status,
    "needs_review",
  );
});
test("expired earned rewards and unrecognized market cannot discount", async () => {
  const s = setup();
  s.docs.get("promotions/promo").markets = ["Atlanta"];
  assert.equal(
    await s.engine.reserveRider({
      rideId: "ride",
      ride: s.ride,
      outcome: s.outcome,
      uid: "rider",
    }),
    null,
  );
  s.docs.set("promotionRewards/expired", {
    userId: "rider",
    audience: "riders",
    status: "available",
    expiresAt: new Date(now - 1),
    offer: { ...s.offer, status: "ended" },
  });
  assert.equal(
    await s.engine.reserveRider({
      rideId: "newride",
      ride: s.ride,
      outcome: s.outcome,
      uid: "rider",
    }),
    null,
  );
});

test("delayed paid-ride delivery honors the original schedule but excludes a paused interval", async () => {
  const s = setup();
  Object.assign(s.docs.get("promotions/promo"), {
    type: "driver_per_ride_bonus",
    audience: "drivers",
    bonusCents: 200,
    status: "ended",
  });
  s.docs.set("drivers/driver", {
    stripeAccountId: "acct_test",
    stripeChargesEnabled: true,
  });
  s.paid("past");
  await s.engine.settle("past");
  assert.equal(s.transfers.length, 1);
  const blocked = setup();
  Object.assign(blocked.docs.get("promotions/promo"), {
    type: "driver_per_ride_bonus",
    audience: "drivers",
    bonusCents: 200,
    pauseIntervals: [{ startsAt: new Date(now - 2000), endsAt: new Date(now) }],
  });
  blocked.paid();
  await blocked.engine.settle("ride");
  assert.equal(blocked.transfers.length, 0);
  assert.equal(
    [...blocked.docs.keys()].filter((x) => x.startsWith("promotionProgress/"))
      .length,
    0,
  );
});
