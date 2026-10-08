const test = require("node:test");
const assert = require("node:assert/strict");
const { admin } = require("../src/config/firebase");
const {
  createRideRequest,
  deterministicRideId,
  rateObject,
  quoteFingerprint
} = require("../src/services/rideRequestService");

class Snapshot {
  constructor(ref, value) {
    this.ref = ref;
    this.id = ref.id;
    this.exists = value != null;
    this.value = value;
  }
  data() { return this.value; }
}

class Ref {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split("/").at(-1);
  }
  async get() { return new Snapshot(this, this.db.values.get(this.path)); }
}

class Collection {
  constructor(db, path) { this.db = db; this.path = path; }
  doc(id) { return new Ref(this.db, `${this.path}/${id}`); }
}

class FakeDb {
  constructor(values = {}) { this.values = new Map(Object.entries(values)); }
  collection(path) { return new Collection(this, path); }
  async runTransaction(callback) {
    const tx = {
      get: (ref) => ref.get(),
      create: (ref, value) => {
        if (this.values.has(ref.path)) throw new Error("already exists");
        this.values.set(ref.path, value);
      },
      set: (ref, value, options) => {
        const existing = options?.merge ? (this.values.get(ref.path) || {}) : {};
        this.values.set(ref.path, { ...existing, ...value });
      }
    };
    return callback(tx);
  }
}

const routeProvider = async () => ({
  route: {
    name: "Test route",
    distanceMeters: 3701.4912,
    durationSeconds: 480,
    hasTolls: false,
    transportType: "AUTOMOBILE"
  }
});

function createPayload(overrides = {}) {
  return {
    idempotencyKey: "request-0001",
    selectedCandidateId: "driver-1",
    candidateDriverIds: ["driver-1", "driver-2"],
    pickup: "Pickup",
    dropoff: "Dropoff",
    pickupCoordinate: { lat: 33.75, lng: -84.39 },
    dropoffCoordinate: { lat: 33.8, lng: -84.3 },
    rideType: "Rydr Go",
    ...overrides
  };
}

function readyDb() {
  return new FakeDb({
    "riders/rider-1": { accountStatus: "active", verifiedRider: true },
    "drivers/driver-1": {
      isApproved: true,
      accountStatus: "active",
      tierRates: { go: { minimumFare: 8, perMile: 1, perMinute: 0.28 } }
    },
    "publicDriverProfiles/driver-1": {
      isOnline: true,
      availabilityStatus: "available",
      eligibleRideTypes: ["Rydr Go"],
      tierRates: { go: { minimumFare: 99, perMile: 99, perMinute: 99 } }
    }
  });
}

test("deterministic ride IDs make retries stable", () => {
  assert.equal(
    deterministicRideId("rider-1", "request-0001"),
    deterministicRideId("rider-1", "request-0001")
  );
  assert.notEqual(
    deterministicRideId("rider-1", "request-0001"),
    deterministicRideId("rider-1", "request-0002")
  );
});

test("driver rate snapshot is uncapped and includes the driver's minimum fare", () => {
  const rate = rateObject({
    tierRates: { go: { minimumFare: 25, perMile: 9.5, perMinute: 3.25 } }
  }, "Rydr Go");
  assert.equal(rate.minimumFareCents, 2500);
  assert.equal(rate.perMileCents, 950);
  assert.equal(rate.perMinuteCents, 325);
});

test("driver rate lookup accepts legacy display-name keys without falling back to defaults", () => {
  const rate = rateObject({
    tierRates: { "Rydr Go": { minimumFare: 12, perMile: 2.75, perMinute: 0.61 } }
  }, "Rydr");
  assert.equal(rate.minimumFareCents, 1200);
  assert.equal(rate.perMileCents, 275);
  assert.equal(rate.perMinuteCents, 61);
});

test("backend creates the authoritative request, signal, route, quote, and dispatch offer", async () => {
  const db = readyDb();
  const result = await createRideRequest({
    riderId: "rider-1",
    authorization: "Bearer token",
    payload: createPayload(),
    db,
    routeProvider,
    paymentVerifier: async () => true,
    authUserProvider: async () => ({ displayName: "Rider One", photoURL: null }),
    trustedScheduledActivation: true
  });
  const request = db.values.get(`rideRequests/${result.rideId}`);
  const signal = db.values.get(`rideRequestSignals/${result.rideId}`);
  assert.equal(result.duplicate, false);
  assert.equal(request.lifecycleOwner, "backend");
  assert.equal(request.dispatchStatus, "offered");
  assert.equal(request.driverMinimumFareCents, 800);
  assert.equal(request.driverRatePerMileCents, 100);
  assert.equal(request.driverRatePerMinuteCents, 28);
  assert.equal(request.backendDistanceMiles, 2.3);
  assert.equal(request.backendDurationMinutes, 8);
  assert.equal(request.estimatedRiderTotalCents, 1100);
  assert.equal(request.estimatedDriverPayoutCents, 720);
  assert.equal(request.estimatedPlatformShareCents, 380);
  assert.match(request.quoteFingerprint, /^[a-f0-9]{64}$/);
  assert.equal(signal.driverId, "driver-1");
});

test("backend rejects an offline selected driver before writing", async () => {
  const db = readyDb();
  db.values.set("publicDriverProfiles/driver-1", {
    isOnline: false,
    eligibleRideTypes: ["Rydr Go"]
  });
  await assert.rejects(
    createRideRequest({
      riderId: "rider-1",
      authorization: "Bearer token",
      payload: createPayload(),
      db,
      routeProvider,
      paymentVerifier: async () => true,
      authUserProvider: async () => ({}),
      trustedScheduledActivation: true
    }),
    (err) => err.statusCode === 409
  );
  assert.equal([...db.values.keys()].some((key) => key.startsWith("rideRequests/")), false);
});

test("backend rejects a selected driver whose canonical account is suspended", async () => {
  const db = readyDb();
  db.values.set("drivers/driver-1", {
    isApproved: true,
    accountStatus: "suspended",
    tierRates: { go: { minimumFare: 8, perMile: 1, perMinute: 0.28 } }
  });
  await assert.rejects(
    createRideRequest({
      riderId: "rider-1",
      authorization: "Bearer token",
      payload: createPayload(),
      db,
      routeProvider,
      paymentVerifier: async () => true,
      authUserProvider: async () => ({}),
      trustedScheduledActivation: true
    }),
    (err) => err.statusCode === 409
  );
});

test("an idempotent retry returns the original ride without another payment or route call", async () => {
  const db = readyDb();
  let validations = 0;
  const options = {
    riderId: "rider-1",
    authorization: "Bearer token",
    payload: createPayload(),
    db,
    routeProvider: async (...args) => { validations += 1; return routeProvider(...args); },
    paymentVerifier: async () => { validations += 1; return true; },
    authUserProvider: async () => ({}),
    trustedScheduledActivation: true
  };
  const first = await createRideRequest(options);
  const second = await createRideRequest(options);
  assert.equal(second.duplicate, true);
  assert.equal(second.rideId, first.rideId);
  assert.equal(validations, 2);
});

test("standard ride creation requires and consumes the backend match-session fingerprint", async () => {
  const db = readyDb();
  const pickup = { latitude: 33.75, longitude: -84.39 };
  const dropoff = { latitude: 33.8, longitude: -84.3 };
  const route = (await routeProvider()).route;
  const rates = rateObject(db.values.get("drivers/driver-1"), "Rydr Go");
  const fingerprint = quoteFingerprint({ riderId: "rider-1", driverId: "driver-1", rideType: "Rydr Go", pickup, dropoff, route, rates });
  const now = admin.firestore.Timestamp.fromMillis(Date.UTC(2026, 9, 7, 12));
  db.values.set("rideMatchSessions/session-1", {
    riderId: "rider-1",
    rideType: "Rydr Go",
    status: "open",
    expiresAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + 300_000),
    pickupCoordinate: { lat: pickup.latitude, lng: pickup.longitude },
    dropoffCoordinate: { lat: dropoff.latitude, lng: dropoff.longitude },
    backendRoute: route,
    candidateIds: ["driver-1"],
    candidates: [{ driverId: "driver-1", quoteFingerprint: fingerprint }]
  });
  const result = await createRideRequest({
    riderId: "rider-1",
    authorization: "Bearer token",
    payload: createPayload({ matchSessionId: "session-1", quoteFingerprint: fingerprint }),
    db,
    routeProvider,
    paymentVerifier: async () => true,
    authUserProvider: async () => ({}),
    now
  });
  assert.equal(db.values.get("rideMatchSessions/session-1").status, "consumed");
  assert.equal(db.values.get(`rideRequests/${result.rideId}`).quoteFingerprint, fingerprint);

  await assert.rejects(
    createRideRequest({
      riderId: "rider-1",
      authorization: "Bearer token",
      payload: createPayload({
        idempotencyKey: "request-0002",
        matchSessionId: "session-1",
        quoteFingerprint: fingerprint
      }),
      db,
      routeProvider,
      paymentVerifier: async () => true,
      authUserProvider: async () => ({}),
      now
    }),
    (err) => err.statusCode === 409
  );
});
