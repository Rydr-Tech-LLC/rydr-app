const test = require("node:test");
const assert = require("node:assert/strict");
const { calculateOutcome } = require("../src/services/rideFinancialService");
const { ACTIONS } = require("../src/services/rideLifecycleService");

test("driver cancellation before pickup never charges the rider", () => {
  const outcome = calculateOutcome({ rideType: "Rydr Go", status: "driverCancelled", cancelledByRole: "driver", estimatedDistanceMiles: 3, estimatedDurationMinutes: 8, arrivedAtPickupAt: { toMillis: () => 1000 } });
  assert.equal(outcome.outcomeType, "driver_cancellation");
  assert.equal(outcome.finalRiderChargeCents, 0);
  assert.equal(outcome.driverPayoutCents, 0);
});

test("queued rides have an explicit backend-owned promotion action", () => {
  assert.deepEqual(ACTIONS.promote_queue.from, ["accepted"]);
  assert.equal(ACTIONS.promote_queue.status, "accepted");
  assert.ok(ACTIONS.promote_queue.fields.includes("queuedRideStartedAt"));
});

test("Mission Control cancellation is a backend lifecycle action", () => {
  assert.equal(ACTIONS.admin_cancel.status, "adminCancelled");
  assert.equal(ACTIONS.admin_cancel.finalizes, true);
  assert.ok(ACTIONS.admin_cancel.from.includes("inProgress"));
});

test("rider and driver cancellation accept every active status recognized by the apps", () => {
  const activeStatuses = [
    "accepted", "enRouteToPickup", "navigatingToPickup", "arrived", "arrivedAtPickup",
    "waitingForRider", "inProgress", "navigatingToStop", "arrivedAtStop", "waitingAtStop",
    "navigatingToDropoff"
  ];
  for (const status of activeStatuses) {
    assert.ok(ACTIONS.rider_cancel.from.includes(status), `rider cancellation must support ${status}`);
    assert.ok(ACTIONS.driver_cancel.from.includes(status), `driver cancellation must support ${status}`);
  }
});

test("admin cancellation is finalized without charging the rider", () => {
  const outcome = calculateOutcome({
    rideType: "Rydr Go",
    status: "adminCancelled",
    cancelledByRole: "admin",
    estimatedDistanceMiles: 3,
    estimatedDurationMinutes: 8,
    driverMinimumFareCents: 700,
    driverRatePerMileCents: 100,
    driverRatePerMinuteCents: 25
  });
  assert.equal(outcome.finalRiderChargeCents, 0);
  assert.equal(outcome.driverPayoutCents, 0);
});
