const test = require("node:test");
const assert = require("node:assert/strict");
const { isApprovedDriver, normalizedLocation, normalizedRideTypes } = require("../src/services/driverPresenceService");

test("driver presence approval rejects safety holds and suspensions", () => {
  assert.equal(isApprovedDriver({ driverApprovalStatus: "approved" }), true);
  assert.equal(isApprovedDriver({ isApproved: true, safetyHold: true }), false);
  assert.equal(isApprovedDriver({ isApproved: true, accountStatus: "suspended" }), false);
  assert.equal(isApprovedDriver({ approvalStatus: "pending" }), false);
});

test("presence location accepts valid coordinates and rejects invalid ones", () => {
  assert.deepEqual(normalizedLocation({ lat: 33.749, lng: -84.388, speed: 4 }), { lat: 33.749, lng: -84.388, speed: 4 });
  assert.equal(normalizedLocation({ lat: 120, lng: -84 }), null);
});

test("presence ride types are trimmed and deduplicated", () => {
  assert.deepEqual(normalizedRideTypes(["Rydr Go", " Rydr Go ", "Rydr XL", ""]), ["Rydr Go", "Rydr XL"]);
});
