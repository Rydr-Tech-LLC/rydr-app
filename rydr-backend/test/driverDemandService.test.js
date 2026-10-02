const test = require("node:test");
const assert = require("node:assert/strict");
const {
  demandLevelForCount,
  suggestedRatesFor,
  countNearbySignals,
  demandSnapshotForSignals
} = require("../src/services/driverDemandService");
const { serverRateFields } = require("../src/services/rideLifecycleService");

test("demand thresholds follow the low, moderate, and high policy", () => {
  assert.equal(demandLevelForCount(0), "low");
  assert.equal(demandLevelForCount(1), "moderate");
  assert.equal(demandLevelForCount(2), "moderate");
  assert.equal(demandLevelForCount(3), "high");
});

test("suggested rates use tier baselines and backend demand adjustments", () => {
  assert.deepEqual(suggestedRatesFor("Rydr Go", "low"), {
    rideType: "go",
    demandLevel: "low",
    minimumFareCents: 700,
    perMileCents: 90,
    perMinuteCents: 15
  });
  assert.deepEqual(suggestedRatesFor("Rydr Prestine", "moderate"), {
    rideType: "prestine",
    demandLevel: "moderate",
    minimumFareCents: 700,
    perMileCents: 160,
    perMinuteCents: 45
  });
  assert.deepEqual(suggestedRatesFor("Rydr Executive", "high"), {
    rideType: "executive",
    demandLevel: "high",
    minimumFareCents: 700,
    perMileCents: 220,
    perMinuteCents: 70
  });
});

test("nearby demand excludes other tiers, expired requests, and distant pickups", () => {
  const nowMillis = 1_700_000_000_000;
  const signals = [
    { status: "pending", rideType: "Rydr Go", pickupCoordinate: { lat: 33.75, lng: -84.39 }, expiresAt: { toMillis: () => nowMillis + 60_000 } },
    { status: "pending", rideType: "Rydr XL", pickupCoordinate: { lat: 33.75, lng: -84.39 }, expiresAt: { toMillis: () => nowMillis + 60_000 } },
    { status: "pending", rideType: "Rydr Go", pickupCoordinate: { lat: 34.75, lng: -84.39 }, expiresAt: { toMillis: () => nowMillis + 60_000 } },
    { status: "pending", rideType: "Rydr Go", pickupCoordinate: { lat: 33.75, lng: -84.39 }, expiresAt: { toMillis: () => nowMillis - 1 } }
  ];
  assert.equal(countNearbySignals(signals, { lat: 33.749, lng: -84.388 }, "Rydr Go", nowMillis), 1);
});

test("snapshot returns backend suggested rates for every requested tier", () => {
  const snapshot = demandSnapshotForSignals({
    signals: [
      { status: "pending", rideType: "Rydr Go", pickupGeoPoint: { latitude: 33.75, longitude: -84.39 } },
      { status: "pending", rideType: "Rydr Go", pickupGeoPoint: { latitude: 33.76, longitude: -84.39 } },
      { status: "pending", rideType: "Rydr XL", pickupGeoPoint: { latitude: 33.75, longitude: -84.39 } }
    ],
    center: { lat: 33.749, lng: -84.388 },
    rideTypes: ["Rydr Go", "Rydr XL"]
  });
  assert.equal(snapshot.byRideType.go.level, "moderate");
  assert.equal(snapshot.byRideType.go.suggestedRates.perMileCents, 110);
  assert.equal(snapshot.byRideType.xl.level, "moderate");
  assert.equal(snapshot.byRideType.xl.suggestedRates.perMileCents, 135);
  assert.equal(snapshot.level, "high");
});

test("ride acceptance ignores client-stored amounts when suggested pricing is enabled", () => {
  const driver = {
    tierRates: {
      go: {
        minimumFare: 999,
        perMile: 999,
        perMinute: 999,
        useSuggestedPricing: true
      }
    }
  };
  const fields = serverRateFields(driver, "Rydr Go", "high");
  assert.equal(fields.driverMinimumFareCents, 700);
  assert.equal(fields.driverRatePerMileCents, 120);
  assert.equal(fields.driverRatePerMinuteCents, 45);
  assert.equal(fields.acceptedDemandLevel, "high");
  assert.equal(fields.driverUsesSuggestedPricing, true);
});
