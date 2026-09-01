const test = require("node:test");
const assert = require("node:assert/strict");
const { coordinateFrom, routePoints } = require("../src/services/rideRouteService");

test("coordinate parser accepts Firestore GeoPoint and app coordinate shapes", () => {
  assert.deepEqual(coordinateFrom({ latitude: 33.7, longitude: -84.4 }), { latitude: 33.7, longitude: -84.4 });
  assert.deepEqual(coordinateFrom({ lat: 33.8, lng: -84.3 }), { latitude: 33.8, longitude: -84.3 });
  assert.equal(coordinateFrom({ lat: 100, lng: -84.3 }), null);
});

test("ride route includes an added stop when present", () => {
  assert.deepEqual(routePoints({
    pickupCoordinate: { lat: 33.7, lng: -84.4 },
    stopGeoPoint: { latitude: 33.75, longitude: -84.35 },
    dropoffCoordinate: { lat: 33.8, lng: -84.3 }
  }), [
    { latitude: 33.7, longitude: -84.4 },
    { latitude: 33.75, longitude: -84.35 },
    { latitude: 33.8, longitude: -84.3 }
  ]);
});
