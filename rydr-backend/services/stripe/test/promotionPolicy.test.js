const { test } = require("node:test");
const assert = require("node:assert/strict");
const p = require("../promotionPolicy");
const outcome = {
  grossChargeCents: 2700,
  finalRiderChargeCents: 2700,
  rideSubtotalCents: 2000,
  bookingFeeCents: 500,
  waitChargeCents: 200,
  driverPayoutCents: 1800,
  platformShareCents: 900,
  calculationInputs: { billableDistance: 20 },
};
test("distance credit covers proportional fare and whole booking fee, leaving extras and full driver pay", () => {
  const discount = p.discountCents(
    { discountKind: "free_ride", limitKind: "distance", maxDistanceMiles: 10 },
    outcome,
    {},
  );
  assert.equal(discount, 1500);
  const actual = p.financialAfterPromotion(outcome, discount);
  assert.equal(actual.finalRiderChargeCents, 1200);
  assert.equal(actual.driverPayoutCents, 1800);
  assert.equal(actual.platformShareCents, 900);
  assert.equal(actual.platformPromotionSubsidyCents, 1500);
  assert.equal(
    require("../financialOutcome").normalizeFinancialOutcome({
      ...actual,
      status: "paid",
    }).ok,
    true,
  );
});
test("within distance cap fare and booking fee are free but wait is paid", () => {
  assert.equal(
    p.discountCents(
      {
        discountKind: "free_ride",
        limitKind: "distance",
        maxDistanceMiles: 25,
      },
      outcome,
      {},
    ),
    2500,
  );
  assert.equal(
    p.discountCents(
      {
        discountKind: "free_ride",
        limitKind: "distance",
        maxDistanceMiles: 10,
        payExcessFare: false,
      },
      outcome,
      {},
    ),
    0,
  );
  assert.equal(
    p.discountCents(
      {
        discountKind: "free_ride",
        limitKind: "distance",
        maxDistanceMiles: 10,
      },
      { ...outcome, calculationInputs: {} },
      {},
    ),
    0,
  );
});
test("percentage and dollar credit exclude extras and respect caps", () => {
  assert.equal(
    p.discountCents(
      { discountKind: "percent", discountPercent: 50 },
      outcome,
      {},
    ),
    1250,
  );
  assert.equal(
    p.discountCents(
      { discountKind: "percent", discountPercent: 100, maxDiscountCents: 1000 },
      outcome,
      {},
    ),
    1000,
  );
  assert.equal(
    p.discountCents(
      { discountKind: "fixed", discountCents: 9999 },
      outcome,
      {},
    ),
    2500,
  );
  assert.equal(
    p.discountCents(
      {
        type: "rider_milestone_reward",
        rewardKind: "fixed",
        rewardCents: 700,
        discountCents: 900,
      },
      outcome,
      {},
    ),
    700,
  );
});
test("Eastern schedules retain clock time in summer and winter and reject missing DST hour", () => {
  assert.equal(
    p.localTimeToISO("2026-10-14T09:00"),
    "2026-10-14T13:00:00.000Z",
  );
  assert.equal(
    p.localTimeToISO("2026-12-14T09:00"),
    "2026-12-14T14:00:00.000Z",
  );
  assert.throws(() => p.localTimeToISO("2027-03-14T02:30"), /does not exist/);
});
test("codes, caps and audiences fail closed", () => {
  assert.equal(
    p.normalizeMechanics(
      { applicationMode: "code", promoCode: " beta-ride " },
      "active",
    ).promoCode,
    "BETA-RIDE",
  );
  for (const promoCode of ["RB-ABCD-EFGH", "ab", "abc/def"])
    assert.throws(() => p.normalizeMechanics({ promoCode }));
  assert.throws(() =>
    p.normalizeMechanics({ applicationMode: "code" }, "active"),
  );
  assert.throws(() =>
    p.validateOffer({
      type: "driver_per_ride_bonus",
      bonusCents: 100,
      perUserLimit: 0,
    }),
  );
  assert.equal(
    p.audienceEligible(
      { audienceRule: "beta" },
      "u",
      { hasRydrRiderAccess: true },
      0,
    ),
    false,
  );
  assert.equal(
    p.audienceEligible({ applicationMode: "code" }, "u", {}, 0),
    false,
  );
  assert.equal(
    p.audienceEligible({ audienceRule: "new" }, "u", {}, 1, true),
    true,
  );
});
test("schedule, market and tier eligibility use authoritative ride and reject invalid timestamps", () => {
  const campaign = {
    status: "active",
    startsAt: new Date(0),
    endsAt: new Date(10000),
    markets: ["Atlanta"],
    rideTypes: ["Rydr Go"],
  };
  assert.equal(
    p.rideEligible(
      campaign,
      {
        pickupCoordinate: { latitude: 33.75, longitude: -84.39 },
        rideType: "go",
      },
      5000,
    ),
    true,
  );
  assert.equal(
    p.rideEligible(campaign, { market: "NYC", rideType: "go" }, 5000),
    false,
  );
  assert.equal(
    p.rideEligible(
      { ...campaign, startsAt: null },
      { market: "ATL", rideType: "go" },
      5000,
    ),
    false,
  );
  assert.equal(
    p.rideEligible(campaign, { market: "ATL", rideType: "go" }, 10000),
    false,
  );
});

test("asynchronous payment success settles the reserved discount once and verifies fare ownership", () => {
  const { paidOutcomeForIntent } = require("../financialOutcome");
  const financial = {
    ...outcome,
    status: "finalized",
    outcomeType: "completed",
  };
  const ride = { riderId: "rider", driverId: "driver" };
  const intent = {
    id: "pi_1",
    amount: 2200,
    currency: "usd",
    metadata: { riderId: "rider", driverId: "driver" },
  };
  const result = paidOutcomeForIntent(financial, ride, intent, {
    discountCents: 500,
    promotionId: "promo",
  });
  assert.equal(result.driverPayoutCents, 1800);
  assert.equal(result.finalRiderChargeCents, 2200);
  assert.equal(
    paidOutcomeForIntent(result, ride, intent, { discountCents: 500 }),
    null,
  );
  assert.throws(
    () =>
      paidOutcomeForIntent(
        financial,
        ride,
        { ...intent, amount: 1 },
        { discountCents: 500 },
      ),
    /amount_mismatch/,
  );
  assert.throws(
    () =>
      paidOutcomeForIntent(
        financial,
        ride,
        { ...intent, metadata: { riderId: "other", driverId: "driver" } },
        { discountCents: 500 },
      ),
    /owner_mismatch/,
  );
});

test("null distance never becomes an eligible zero-mile trip", () => {
  assert.equal(
    p.discountCents(
      {
        discountKind: "free_ride",
        limitKind: "distance",
        maxDistanceMiles: 10,
      },
      { ...outcome, calculationInputs: { billableDistance: null } },
      { backendDistanceMiles: null, estimatedDistanceMiles: null },
    ),
    0,
  );
});
