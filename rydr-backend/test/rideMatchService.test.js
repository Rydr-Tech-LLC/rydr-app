const test = require("node:test");
const assert = require("node:assert/strict");
const { publicDriverProjection } = require("../src/services/rideMatchService");

test("match candidates expose only rider-safe display data", () => {
  const projection = publicDriverProjection({
    displayName: "Taylor Driver",
    email: "private@example.com",
    phoneNumber: "+15555550123",
    profilePhotoURL: "https://example.com/profile.jpg",
    vehicle: { color: "Black", year: 2025, make: "Toyota", model: "Camry", licensePlate: "PRIVATE" },
    rating: 4.9,
    ratingCount: 31,
    completedRideCount: 84,
    acceptanceRate: 96,
    compliments: ["Safe driver", "Great conversation"]
  }, { latitude: 33.749, longitude: -84.388 });

  assert.equal(projection.displayName, "Taylor");
  assert.equal(projection.vehicleSummary, "Black 2025 Toyota Camry");
  assert.deepEqual(projection.approximateLocation, { lat: 33.749, lng: -84.388 });
  assert.equal(projection.email, undefined);
  assert.equal(projection.phoneNumber, undefined);
  assert.equal(projection.licensePlate, undefined);
});

test("match candidate projection supplies stable display fallbacks", () => {
  const projection = publicDriverProjection({}, { latitude: 1, longitude: 2 });
  assert.equal(projection.displayName, "Rydr Driver");
  assert.equal(projection.vehicleSummary, "Verified Rydr vehicle");
  assert.equal(projection.rating, 5);
});
