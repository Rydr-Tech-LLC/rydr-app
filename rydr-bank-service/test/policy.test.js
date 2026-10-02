import test from "node:test";
import assert from "node:assert/strict";
import { completedRideEvidence, createWebBookingTokenForTest, verifyWebBookingToken } from "../policy.js";

test("completed ride evidence ignores client values and uses backend-owned ride fields", () => {
  const result = completedRideEvidence({
    riderId: "rider-1",
    status: "completed",
    lifecycleOwner: "backend",
    financialOutcomeStatus: "finalized",
    backendDistanceMiles: 8.25,
    rideType: "Rydr Go",
  }, "rider-1");
  assert.deepEqual(result, { distanceMi: 8.25, rideType: "Rydr Go" });
});

test("completed ride evidence rejects the wrong rider and unfinished rides", () => {
  assert.throws(
    () => completedRideEvidence({ riderId: "other", status: "completed", hasFinancialOutcome: true, backendDistanceMiles: 5, rideType: "Rydr Go" }, "rider-1"),
    /not_ride_rider/,
  );
  assert.throws(
    () => completedRideEvidence({ riderId: "rider-1", status: "inProgress", hasFinancialOutcome: true, backendDistanceMiles: 5, rideType: "Rydr Go" }, "rider-1"),
    /ride_not_completed/,
  );
  assert.throws(
    () => completedRideEvidence({ riderId: "rider-1", status: "completed", backendDistanceMiles: 5, rideType: "Rydr Go" }, "rider-1"),
    /ride_not_backend_finalized/,
  );
});

test("signed web booking authorization binds action and booking evidence", () => {
  const secret = "a-test-secret-that-is-not-used-in-production";
  const claims = {
    action: "consume",
    code: "RB-ABCD-EFGH",
    email: "friend@example.com",
    bookingId: "",
    rideId: "ride-1",
    rideType: "Rydr Go",
    distanceMi: 4.2,
    exp: 1_000,
  };
  const token = createWebBookingTokenForTest(claims, secret);
  assert.equal(verifyWebBookingToken({ token, secret, expected: claims, nowSeconds: 900 }).rideId, "ride-1");
  assert.throws(
    () => verifyWebBookingToken({ token, secret, expected: { ...claims, rideId: "ride-2" }, nowSeconds: 900 }),
    /booking_token_mismatch/,
  );
  assert.throws(
    () => verifyWebBookingToken({ token, secret, expected: claims, nowSeconds: 1_001 }),
    /expired_booking_token/,
  );
});
