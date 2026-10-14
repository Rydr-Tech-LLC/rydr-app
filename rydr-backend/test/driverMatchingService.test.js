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

test("Prestine body choices filter actual matches by premium eligibility and selected vehicle", () => {
  const validUntil = Date.now() + 86400000;
  const premium = bodyType => ({ bodyType, prestine: { eligible: true, validUntil } });
  const candidates = [
    candidate("premium-suv", { eligibleRideTypes: ["Rydr Prestine SUV"], premiumEligibility: premium("suv") }),
    candidate("premium-sedan", { eligibleRideTypes: ["Rydr Prestine Sedan"], premiumEligibility: premium("sedan") }),
    candidate("ordinary-suv", { eligibleRideTypes: ["Rydr Prestine SUV"], vehicle: { make: "Toyota", model: "RAV4", year: 2025 } }),
    candidate("expired-premium", { eligibleRideTypes: ["Rydr Prestine SUV"], premiumEligibility: { bodyType: "suv", prestine: { eligible: true, validUntil: Date.now() - 1 } } })
  ];
  assert.deepEqual(match(candidates, { rideType: "Rydr Prestine SUV" }).map(row => row.id), ["premium-suv"]);
  assert.deepEqual(match(candidates, { rideType: "Rydr Prestine Sedan" }).map(row => row.id), ["premium-sedan"]);
});
