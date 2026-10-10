const test = require("node:test");
const assert = require("node:assert/strict");
const { getDriverRateCard, normalizeTierRates, timestampMillis } = require("../src/services/driverRateCardService");

class FakeSnapshot {
  constructor(value) { this.exists = value != null; this.value = value; }
  data() { return this.value; }
}
class FakeRef {
  constructor(db, path) { this.db = db; this.path = path; }
}
class FakeCollection {
  constructor(db, path) { this.db = db; this.path = path; }
  doc(id) { return new FakeRef(this.db, `${this.path}/${id}`); }
}
class FakeDb {
  constructor(values) { this.values = new Map(Object.entries(values)); }
  collection(name) { return new FakeCollection(this, name); }
  async runTransaction(callback) {
    const tx = {
      get: async (ref) => new FakeSnapshot(this.values.get(ref.path)),
      set: (ref, value) => this.values.set(ref.path, { ...(this.values.get(ref.path) || {}), ...value })
    };
    return callback(tx);
  }
}

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

test("rate card timestamps support Firestore timestamp shapes", () => {
  assert.equal(timestampMillis({ seconds: 42 }), 42_000);
  assert.equal(timestampMillis({ _seconds: 84 }), 84_000);
  assert.equal(timestampMillis({ toMillis: () => 126_000 }), 126_000);
  assert.equal(timestampMillis(undefined), 0);
});

test("authenticated rate-card reads reconcile a newer public card into the driver profile", async () => {
  const db = new FakeDb({
    "drivers/driver-1": {
      rateCardUpdatedAt: { seconds: 10 },
      tierRates: { go: { minimumFare: 8, perMile: 1, perMinute: 0.5 } }
    },
    "publicDriverProfiles/driver-1": {
      rateCardUpdatedAt: { seconds: 20 },
      tierRates: { "Rydr Go": { minimumFare: 12, perMile: 1.75, perMinute: 0.8 } }
    }
  });
  const result = await getDriverRateCard({ uid: "driver-1", db });
  assert.equal(result.tierRates.go.minimumFare, 12);
  assert.equal(db.values.get("drivers/driver-1").tierRates.go.perMile, 1.75);
  assert.equal(db.values.get("publicDriverProfiles/driver-1").tierRates.go.perMinute, 0.8);
});
