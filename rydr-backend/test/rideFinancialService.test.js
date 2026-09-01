const test = require("node:test");
const assert = require("node:assert/strict");
const { calculateOutcome, applyFullRideCredit } = require("../src/services/rideFinancialService");

test("short Rydr Go ride applies minimum and booking fee in integer cents", () => {
  const outcome = calculateOutcome({ rideType: "Rydr Go", estimatedDistanceMiles: 2, estimatedDurationMinutes: 5, driverRatePerMileCents: 50, driverRatePerMinuteCents: 15, status: "completed" });
  assert.equal(outcome.rideSubtotalCents, 700);
  assert.equal(outcome.bookingFeeCents, 300);
  assert.equal(outcome.finalRiderChargeCents, 1000);
  assert.equal(outcome.driverPayoutCents, 490);
  assert.equal(outcome.platformShareCents, 510);
});

test("post-arrival cancellation is calculated without client amounts", () => {
  const at = { toMillis: () => 1000 };
  const outcome = calculateOutcome({ rideType: "Rydr Go", estimatedDistanceMiles: 2, estimatedDurationMinutes: 5, driverRatePerMileCents: 50, driverRatePerMinuteCents: 15, status: "riderCancelled", arrivedAtPickupAt: at });
  assert.equal(outcome.cancellationFeeCents, 140);
  assert.equal(outcome.finalRiderChargeCents, 440);
});

test("driver rates are clamped to the backend tier policy", () => {
  const outcome = calculateOutcome({ rideType: "Rydr Executive", estimatedDistanceMiles: 10, estimatedDurationMinutes: 10, driverRatePerMileCents: 9999, driverRatePerMinuteCents: 9999, status: "completed" });
  assert.equal(outcome.distanceChargeCents, 2000);
  assert.equal(outcome.timeChargeCents, 500);
});

test("Apple Maps distance and duration override legacy client estimates", () => {
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    backendDistanceMiles: 4,
    backendDurationMinutes: 12,
    estimatedDistanceMiles: 1,
    estimatedDurationMinutes: 1,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 25,
    status: "completed"
  });
  assert.equal(outcome.distanceChargeCents, 400);
  assert.equal(outcome.timeChargeCents, 300);
  assert.equal(outcome.calculationInputs.evidenceSource, "backend_route");
});

test("RydrBank credit zeroes the rider charge without reducing driver economics", () => {
  const base = calculateOutcome({ rideType: "Rydr Go", estimatedDistanceMiles: 2, estimatedDurationMinutes: 5, driverRatePerMileCents: 50, driverRatePerMinuteCents: 15, status: "completed" });
  const credited = applyFullRideCredit(base, "RB-TEST-CODE");
  assert.equal(credited.grossChargeCents, 1000);
  assert.equal(credited.promotionDiscountCents, 1000);
  assert.equal(credited.finalRiderChargeCents, 0);
  assert.equal(credited.driverPayoutCents, 490);
  assert.equal(credited.platformShareCents, 510);
});
