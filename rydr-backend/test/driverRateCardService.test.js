const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeTierRates } = require("../src/services/driverRateCardService");

test("rate cards normalize legacy display-name keys to canonical tiers", () => {
  const result = normalizeTierRates({
    "Rydr Go": { minimumFare: 11 },
    "Rydr Pristine": { minimumFare: 18 },
    xl: { minimumFare: 14 }
  });
  assert.deepEqual(Object.keys(result).sort(), ["go", "prestine", "xl"]);
  assert.equal(result.go.minimumFare, 11);
  assert.equal(result.prestine.minimumFare, 18);
});
