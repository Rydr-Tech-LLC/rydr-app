const test = require("node:test");
const assert = require("node:assert/strict");
const { findBestDrivers } = require("../src/services/driverMatchingService");

const pickup = { lat: 33.749, lng: -84.388 };
const dropoff = { lat: 33.77, lng: -84.36 };

function candidate(id, overrides = {}) {
  return {
    id,
    profile: {
      isOnline: true,
      availabilityStatus: "available",
      standardDispatchEnabled: true,
      eligibleRideTypes: ["Rydr Go"],
      approximateLocation: pickup,
      rating: 4.8,
      ...overrides
    }
  };
}

function match(candidates, overrides = {}) {
  return findBestDrivers({
    rideType: "Rydr Go",
    pickupCoordinate: pickup,
    dropoffCoordinate: dropoff,
    routeDistanceMiles: 8,
    candidates,
    ...overrides
  });
}

test("matching rejects offline, unavailable, wrong-tier, and temporarily disabled drivers", () => {
  const results = match([
    candidate("eligible"),
    candidate("offline", { isOnline: false }),
    candidate("busy", { availabilityStatus: "offline" }),
    candidate("wrong-tier", { eligibleRideTypes: ["Rydr XL"] }),
    candidate("disabled", { temporarilyDisabledRideTypes: ["Rydr Go"] })
  ]);
  assert.deepEqual(results.map((result) => result.id), ["eligible"]);
});

test("strict preference matches rank ahead of fallback matches", () => {
  const results = match([
    candidate("fallback-close", {
      rideFilters: { prioritizeShorterRides: true }
    }),
    candidate("strict-farther", {
      approximateLocation: { lat: 33.79, lng: -84.388 }
    })
  ], { routeDistanceMiles: 12 });
  assert.deepEqual(results.map((result) => result.id), ["strict-farther", "fallback-close"]);
  assert.equal(results[1].preferenceMatch, "fallback");
});

test("work zones require both pickup and dropoff to stay inside the driver's radius", () => {
  const results = match([
    candidate("inside", { rideFilters: { workZoneEnabled: true, workZoneRadiusMiles: 10 } }),
    candidate("outside", { rideFilters: { workZoneEnabled: true, workZoneRadiusMiles: 1 } })
  ]);
  assert.deepEqual(results.map((result) => result.id), ["inside"]);
});

test("destination mode accepts trips moving toward the destination corridor", () => {
  const results = match([
    candidate("toward-destination", {
      rideFilters: {
        destinationModeEnabled: true,
        destinationCoordinate: { lat: 33.82, lng: -84.30 },
        destinationCorridorMiles: 5
      }
    }),
    candidate("away-from-destination", {
      rideFilters: {
        destinationModeEnabled: true,
        destinationCoordinate: { lat: 33.70, lng: -84.45 },
        destinationCorridorMiles: 5
      }
    })
  ]);
  assert.deepEqual(results.map((result) => result.id), ["toward-destination"]);
  assert.ok(results[0].matchReasons.includes("destination_corridor"));
});

test("scheduled matching may include offline drivers while preserving ranking and limits", () => {
  const results = match([
    candidate("b", { isOnline: false, rating: 4.9 }),
    candidate("a", { isOnline: false, rating: 4.9 })
  ], { requireOnline: false, maxResults: 1 });
  assert.equal(results.length, 1);
  assert.equal(results[0].id, "a");
  assert.equal(typeof results[0].matchScore, "number");
});
