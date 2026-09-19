const test = require("node:test");
const assert = require("node:assert/strict");
const { calculateOutcome, applyFullRideCredit } = require("../src/services/rideFinancialService");

test("driver minimum fare example produces the expected 90/10 split", () => {
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    estimatedDistanceMiles: 2.3,
    estimatedDurationMinutes: 8,
    driverMinimumFareCents: 800,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 28,
    status: "completed"
  });
  assert.equal(outcome.distanceChargeCents, 230);
  assert.equal(outcome.timeChargeCents, 224);
  assert.equal(outcome.minimumFareAdjustmentCents, 346);
  assert.equal(outcome.rideSubtotalCents, 800);
  assert.equal(outcome.bookingFeeCents, 300);
  assert.equal(outcome.finalRiderChargeCents, 1100);
  assert.equal(outcome.driverPayoutCents, 720);
  assert.equal(outcome.platformShareCents, 380);
});

test("driver mile and minute rates are not capped", () => {
  const outcome = calculateOutcome({
    rideType: "Rydr Executive",
    estimatedDistanceMiles: 10,
    estimatedDurationMinutes: 10,
    driverMinimumFareCents: 0,
    driverRatePerMileCents: 9999,
    driverRatePerMinuteCents: 9999,
    status: "completed"
  });
  assert.equal(outcome.distanceChargeCents, 99990);
  assert.equal(outcome.timeChargeCents, 99990);
});

test("post-arrival cancellation is paid fully to the driver", () => {
  const at = { toMillis: () => 1000 };
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    estimatedDistanceMiles: 2,
    estimatedDurationMinutes: 5,
    driverMinimumFareCents: 700,
    driverRatePerMileCents: 50,
    driverRatePerMinuteCents: 15,
    status: "riderCancelled",
    arrivedAtPickupAt: at
  });
  assert.equal(outcome.cancellationFeeCents, 140);
  assert.equal(outcome.finalRiderChargeCents, 440);
  assert.equal(outcome.driverPayoutCents, 140);
  assert.equal(outcome.platformShareCents, 300);
});

test("paid wait on a cancellation remains subject to the 90/10 split", () => {
  const paidWaitStart = { toMillis: () => 1_000 };
  const cancelledAt = { toMillis: () => 121_000 };
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    estimatedDistanceMiles: 2,
    estimatedDurationMinutes: 5,
    driverMinimumFareCents: 700,
    driverRatePerMileCents: 50,
    driverRatePerMinuteCents: 50,
    pickupPaidWaitStartedAt: paidWaitStart,
    arrivedAtPickupAt: paidWaitStart,
    cancelledAt,
    status: "riderCancelled"
  });
  assert.equal(outcome.waitChargeCents, 100);
  assert.equal(outcome.cancellationFeeCents, 140);
  assert.equal(outcome.driverPayoutCents, 230);
  assert.equal(outcome.platformShareCents, 310);
  assert.equal(outcome.finalRiderChargeCents, 540);
});

test("mid-ride cancellation uses telemetry distance and adjusts booking fee", () => {
  const start = { toMillis: () => 1_000 };
  const end = { toMillis: () => 241_000 };
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    backendDistanceMiles: 10,
    backendDurationMinutes: 20,
    backendActualDistanceMiles: 2.3,
    driverMinimumFareCents: 0,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 25,
    rideStartedAt: start,
    cancelledAt: end,
    status: "riderCancelled"
  });
  assert.equal(outcome.distanceChargeCents, 230);
  assert.equal(outcome.timeChargeCents, 100);
  assert.equal(outcome.bookingFeeCents, 300);
  assert.equal(outcome.driverPayoutCents, 297);
  assert.equal(outcome.platformShareCents, 333);
});

test("completed ride charges only time beyond the five-minute ETA grace", () => {
  const start = { toMillis: () => 1_000 };
  const end = { toMillis: () => 1_081_000 };
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    backendDistanceMiles: 1,
    backendDurationMinutes: 10,
    driverMinimumFareCents: 0,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 50,
    rideStartedAt: start,
    completedAt: end,
    status: "completed"
  });
  assert.equal(outcome.calculationInputs.actualMinutes, 18);
  assert.equal(outcome.calculationInputs.timeAdjustmentMinutes, 3);
  assert.equal(outcome.timeAdjustmentCents, 150);
  assert.equal(outcome.timeChargeCents, 650);
});

test("Apple Maps distance and duration override legacy client estimates", () => {
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    backendDistanceMiles: 4,
    backendDurationMinutes: 12,
    estimatedDistanceMiles: 1,
    estimatedDurationMinutes: 1,
    driverMinimumFareCents: 0,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 25,
    status: "completed"
  });
  assert.equal(outcome.distanceChargeCents, 400);
  assert.equal(outcome.timeChargeCents, 300);
  assert.equal(outcome.calculationInputs.evidenceSource, "backend_route");
});

test("replacement rides receive one booking fee credit", () => {
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    estimatedDistanceMiles: 2,
    estimatedDurationMinutes: 5,
    driverMinimumFareCents: 700,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 25,
    bookingFeeCreditCents: 300,
    status: "completed"
  });
  assert.equal(outcome.bookingFeeBeforeCreditCents, 300);
  assert.equal(outcome.bookingFeeCreditCents, 300);
  assert.equal(outcome.bookingFeeCents, 0);
});

test("RydrBank credit zeroes rider charge without reducing driver economics", () => {
  const base = calculateOutcome({
    rideType: "Rydr Go",
    estimatedDistanceMiles: 2,
    estimatedDurationMinutes: 5,
    driverMinimumFareCents: 700,
    driverRatePerMileCents: 50,
    driverRatePerMinuteCents: 15,
    status: "completed"
  });
  const credited = applyFullRideCredit(base, true);
  assert.equal(credited.grossChargeCents, 1000);
  assert.equal(credited.promotionDiscountCents, 1000);
  assert.equal(credited.finalRiderChargeCents, 0);
  assert.equal(credited.driverPayoutCents, 630);
  assert.equal(credited.platformShareCents, 370);
});
