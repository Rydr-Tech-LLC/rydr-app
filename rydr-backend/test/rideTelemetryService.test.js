const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeTelemetry } = require("../src/services/rideTelemetryService");

test("trip telemetry accepts coordinates and bounds supporting evidence", () => {
  assert.deepEqual(normalizeTelemetry({
    lat: 33.75,
    lng: -84.39,
    speed: 12,
    course: 180,
    horizontalAccuracy: 8
  }), {
    lat: 33.75,
    lng: -84.39,
    speed: 12,
    course: 180,
    horizontalAccuracy: 8
  });
  assert.equal(normalizeTelemetry({ lat: 33, lng: -84, speed: -1 }).speed, null);
  assert.throws(() => normalizeTelemetry({ lat: 133, lng: -84 }), /coordinates/);
});
