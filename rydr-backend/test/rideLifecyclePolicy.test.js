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
