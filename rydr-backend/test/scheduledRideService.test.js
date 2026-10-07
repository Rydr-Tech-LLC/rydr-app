const test = require("node:test");
const assert = require("node:assert/strict");
const {
  MINIMUM_LEAD_TIME_MS,
  MAXIMUM_LEAD_TIME_MS,
  ACTIVATION_BUFFER_SECONDS,
  validateSchedule,
  scheduledCandidateEligible,
  quoteFor
} = require("../src/services/scheduledRideService");

test("scheduled rides enforce the two-hour to thirty-day booking window", () => {
  const now = Date.UTC(2026, 9, 7, 12);
  assert.throws(() => validateSchedule(now + MINIMUM_LEAD_TIME_MS - 1, now), /two hours/);
  assert.equal(validateSchedule(now + MINIMUM_LEAD_TIME_MS, now), now + MINIMUM_LEAD_TIME_MS);
  assert.throws(() => validateSchedule(now + MAXIMUM_LEAD_TIME_MS + 1, now), /30 days/);
});

test("scheduled eligibility does not require the driver to be dispatch-online hours in advance", () => {
  assert.equal(scheduledCandidateEligible({
    isOnline: false,
    standardDispatchEnabled: true,
    isApproved: true,
    eligibleRideTypes: ["Rydr Go"]
  }, "Rydr Go"), true);
  assert.equal(scheduledCandidateEligible({
    standardDispatchEnabled: true,
    isApproved: true,
    eligibleRideTypes: ["Rydr XL"]
  }, "Rydr Go"), false);
  assert.equal(scheduledCandidateEligible({
    isOnline: false,
    standardDispatchEnabled: true,
    eligibleRideTypes: ["Rydr Go"]
  }, "Rydr Go"), false);
});

test("scheduled locked quote uses current minimum fare and 90/10 pricing", () => {
  const quote = quoteFor({
    rideType: "Rydr Go",
    route: { distanceMeters: 3701.4912, durationSeconds: 480 },
    rates: {
      minimumFareCents: 800,
      perMileCents: 100,
      perMinuteCents: 28,
      usesSuggestedPricing: false
    }
  });
  assert.deepEqual(quote, {
    totalCents: 1100,
    baseFareCents: 800,
    bookingFeeCents: 300,
    driverPayoutCents: 720,
    platformShareCents: 380
  });
});

test("scheduled activation buffer remains within the proposed five-to-seven minute range", () => {
  assert.equal(ACTIVATION_BUFFER_SECONDS, 360);
});
