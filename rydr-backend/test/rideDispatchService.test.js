const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizedCandidateIds,
  isEligibleCandidate,
  advanceRideDispatch
} = require("../src/services/rideDispatchService");

class FakeSnapshot {
  constructor(ref, value) {
    this.ref = ref;
    this.id = ref.id;
    this.exists = value != null;
    this.value = value;
  }
  data() { return this.value; }
}

class FakeRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split("/").at(-1);
  }
  async get() { return new FakeSnapshot(this, this.db.values.get(this.path)); }
  collection(name) { return new FakeCollection(this.db, `${this.path}/${name}`); }
}

class FakeCollection {
  constructor(db, path) { this.db = db; this.path = path; }
  doc(id) { return new FakeRef(this.db, `${this.path}/${id}`); }
}

class FakeDb {
  constructor(values) { this.values = new Map(Object.entries(values)); }
  collection(name) { return new FakeCollection(this, name); }
  async getAll(...refs) { return Promise.all(refs.map((ref) => ref.get())); }
  async runTransaction(callback) {
    const tx = {
      get: (ref) => ref.get(),
      set: (ref, value, options) => {
        const existing = options?.merge ? (this.values.get(ref.path) || {}) : {};
        this.values.set(ref.path, { ...existing, ...value });
      }
    };
    return callback(tx);
  }
}

test("candidate IDs are sanitized, deduplicated, and bounded", () => {
  const values = ["driver-1", "driver-1", "bad id", "driver_2", ...Array.from({ length: 30 }, (_, index) => `d${index}`)];
  const result = normalizedCandidateIds(values);
  assert.deepEqual(result.slice(0, 2), ["driver-1", "driver_2"]);
  assert.equal(result.length, 20);
});

test("backend eligibility rejects offline and wrong-tier candidates", () => {
  assert.equal(isEligibleCandidate({ isOnline: true, eligibleRideTypes: ["Rydr Go"] }, "Rydr Go"), true);
  assert.equal(isEligibleCandidate({ isOnline: false, eligibleRideTypes: ["Rydr Go"] }, "Rydr Go"), false);
  assert.equal(isEligibleCandidate({ isOnline: true, eligibleRideTypes: ["Rydr XL"] }, "Rydr Go"), false);
});

test("decline advances to the next backend-validated candidate and records the attempt", async () => {
  const db = new FakeDb({
    "rideRequests/ride-1": {
      riderId: "rider-1",
      driverId: "driver-1",
      rideType: "Rydr Go",
      status: "pending",
      dispatchStatus: "offered",
      dispatchAttemptNumber: 1,
      dispatchCandidateIds: ["driver-1", "driver-2"],
      attemptedDriverIds: []
    },
    "publicDriverProfiles/driver-2": {
      isOnline: true,
      availabilityStatus: "available",
      eligibleRideTypes: ["Rydr Go"],
      rating: 5
    },
    "drivers/driver-2": { isApproved: true, accountStatus: "active" },
    "driver_status/driver-2": {
      isOnline: true,
      availabilityStatus: "available",
      presenceExpiresAt: { seconds: 4_000_000_000 }
    }
  });
  const result = await advanceRideDispatch({
    rideId: "ride-1",
    actorUid: "driver-1",
    actorRole: "driver",
    reason: "declined",
    requestId: "request-0001",
    db
  });
  assert.equal(result.status, "pending");
  assert.equal(result.driverId, "driver-2");
  assert.deepEqual(result.attemptedDriverIds, ["driver-1"]);
  assert.equal(db.values.get("rideRequests/ride-1/dispatchAttempts/0001").outcome, "declined");

  const duplicate = await advanceRideDispatch({
    rideId: "ride-1",
    actorUid: "driver-1",
    actorRole: "driver",
    reason: "declined",
    requestId: "request-0001",
    db
  });
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.driverId, "driver-2");
});

test("exhausting the candidate pool creates a terminal backend state", async () => {
  const db = new FakeDb({
    "rideRequests/ride-2": {
      riderId: "rider-1",
      driverId: "driver-1",
      rideType: "Rydr Go",
      status: "pending",
      dispatchStatus: "offered",
      dispatchAttemptNumber: 1,
      dispatchCandidateIds: ["driver-1"],
      attemptedDriverIds: []
    }
  });
  const result = await advanceRideDispatch({
    rideId: "ride-2",
    actorUid: "driver-1",
    actorRole: "driver",
    reason: "missed",
    requestId: "request-0002",
    db
  });
  assert.equal(result.status, "noDriversAvailable");
  assert.equal(result.dispatchStatus, "noDriversAvailable");
  assert.equal(db.values.get("rideRequestSignals/ride-2").status, "closed");
});
