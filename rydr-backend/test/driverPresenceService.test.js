const test = require("node:test");
const assert = require("node:assert/strict");
const { isApprovedDriver, normalizedLocation, normalizedRideTypes, cashHubRequestShouldIncludeDriver } = require("../src/services/driverPresenceService");

test("driver presence approval rejects safety holds and suspensions", () => {
  assert.equal(isApprovedDriver({ driverApprovalStatus: "approved" }), true);
  assert.equal(isApprovedDriver({ isApproved: true, safetyHold: true }), false);
  assert.equal(isApprovedDriver({ isApproved: true, accountStatus: "suspended" }), false);
  assert.equal(isApprovedDriver({ isApproved: true, accountStatus: "deletion_requested" }), false);
  assert.equal(isApprovedDriver({ approvalStatus: "pending" }), false);
});

test("presence location accepts valid coordinates and rejects invalid ones", () => {
  assert.deepEqual(normalizedLocation({ lat: 33.749, lng: -84.388, speed: 4 }), { lat: 33.749, lng: -84.388, speed: 4 });
  assert.equal(normalizedLocation({ lat: 120, lng: -84 }), null);
});

test("presence ride types are trimmed and deduplicated", () => {
  assert.deepEqual(normalizedRideTypes(["Rydr Go", " Rydr Go ", "Rydr XL", ""]), ["Rydr Go", "Rydr XL"]);
});

test("Cash Hub presence reconciles a driver into eligible nearby open posts", () => {
  const nearby = {
    status: "open",
    visibility: "Public CashRydr Hub Community",
    pickupCoordinate: { latitude: 33.749, longitude: -84.388 }
  };
  assert.equal(cashHubRequestShouldIncludeDriver(nearby, "driver-a", { lat: 33.76, lng: -84.39 }), true);
  assert.equal(cashHubRequestShouldIncludeDriver(nearby, "driver-a", { lat: 34.75, lng: -84.39 }), false);
  assert.equal(cashHubRequestShouldIncludeDriver({ ...nearby, status: "connected" }, "driver-a", { lat: 33.76, lng: -84.39 }), false);
});

test("Cash Hub favorite visibility only includes allowed drivers", () => {
  const request = {
    status: "open",
    visibility: "Favorite Drivers",
    allowedDriverUids: ["driver-a"]
  };
  assert.equal(cashHubRequestShouldIncludeDriver(request, "driver-a", null), true);
  assert.equal(cashHubRequestShouldIncludeDriver(request, "driver-b", null), false);
});
