"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

process.env.GCLOUD_PROJECT = "demo-rydr-scheduled-rides";
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: process.env.GCLOUD_PROJECT });

const admin = require("firebase-admin");
const {
  DEFAULT_SCHEDULED_RIDES_CONFIG,
  calculateScheduledRideQuote,
  maximumScheduledRideQuote,
  scheduleLockWindow,
  scheduledRidesConfigFromData
} = require("../lib/scheduledRides/domain");
const {
  createScheduledRideRequestForUser,
  previewScheduledRidePriceForUser,
  respondToScheduledRideForUser,
  selectScheduledRideOfferForUser
} = require("../lib/scheduledRides/service");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc } = require("firebase/firestore");

const projectId = process.env.GCLOUD_PROJECT;
const now = Date.now();
const scheduledAt = now + 4 * 60 * 60 * 1000;
const routeEstimate = { distanceMiles: 10, durationMinutes: 20, source: "MapKit", version: "test-v1" };

function requestInput(requestId, selectionMode, approvedMaximumCents) {
  return {
    requestId,
    selectionMode,
    rideType: "go",
    pickup: { address: "100 First St", latitude: 33.45, longitude: -112.07, area: "Phoenix" },
    destination: { address: "200 Second St", latitude: 33.51, longitude: -112.03, area: "Phoenix" },
    routeEstimate,
    scheduledAtEpochMs: scheduledAt,
    timeZone: "America/Phoenix",
    approvedMaximumCents,
    preferences: { requiredCapabilities: [], requiredVehicleAttributes: {}, allowAutomaticReplacement: false }
  };
}

async function seedDriver(db, uid, perMile = 0.8, perMinute = 0.2) {
  await Promise.all([
    db.collection("drivers").doc(uid).set({
      driverApprovalStatus: "approved",
      selectedRideTypes: ["Rydr Go"],
      tierRates: { go: { perMile, perMinute } },
      vehicle: { make: "Test", model: "Car" }
    }),
    db.collection("driver_status").doc(uid).set({ hasActiveRide: false }),
    db.collection("publicDriverProfiles").doc(uid).set({ displayName: uid, rating: 4.9 })
  ]);
}

test("scheduled rides Firebase foundation", async (t) => {
  const db = admin.apps.length ? admin.firestore() : admin.initializeApp({ projectId }).firestore();
  await db.collection("platformConfig").doc("scheduledRides").set({
    ...DEFAULT_SCHEDULED_RIDES_CONFIG,
    enabled: true,
    minimumLeadMinutes: 15
  });
  const maximum = maximumScheduledRideQuote(
    routeEstimate,
    DEFAULT_SCHEDULED_RIDES_CONFIG.pricingTiers.go,
    DEFAULT_SCHEDULED_RIDES_CONFIG.pricingVersion,
    DEFAULT_SCHEDULED_RIDES_CONFIG.driverPayoutBasisPoints
  ).riderBaseFareCents;

  await t.test("server quote uses bounded integer-cent rates and minimum fare", () => {
    const quote = calculateScheduledRideQuote(
      { distanceMiles: 1, durationMinutes: 2, source: "MapKit", version: "v1" },
      DEFAULT_SCHEDULED_RIDES_CONFIG.pricingTiers.go,
      999,
      999,
      "v1",
      7000
    );
    assert.equal(quote.driverRatePerMileCents, 100);
    assert.equal(quote.driverRatePerMinuteCents, 25);
    assert.equal(quote.rideSubtotalCents, 700);
    assert.equal(quote.riderBaseFareCents, 1000);
  });

  await t.test("configuration fails closed and lock windows are deterministic", () => {
    assert.equal(scheduledRidesConfigFromData(undefined).enabled, false);
    const window = scheduleLockWindow(scheduledAt, 20, DEFAULT_SCHEDULED_RIDES_CONFIG);
    assert.ok(window.startsAtMs < scheduledAt);
    assert.ok(window.endsAtMs > scheduledAt);
    assert.ok(window.bucketStartsAtMs.length > 1);
  });

  await t.test("Quick Schedule transaction assigns only the first eligible driver", async () => {
    await Promise.all([seedDriver(db, "quick-driver-a"), seedDriver(db, "quick-driver-b")]);
    await createScheduledRideRequestForUser("rider-quick", requestInput("quick-request-001", "quick", maximum), now);
    const results = await Promise.allSettled([
      respondToScheduledRideForUser("quick-driver-a", { requestId: "quick-request-001" }),
      respondToScheduledRideForUser("quick-driver-b", { requestId: "quick-request-001" })
    ]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    const snapshot = await db.collection("scheduledRideRequests").doc("quick-request-001").get();
    assert.equal(snapshot.get("status"), "confirmed");
    assert.ok(["quick-driver-a", "quick-driver-b"].includes(snapshot.get("assignedDriverId")));
    const lock = await snapshot.ref.collection("priceLocks").doc("v1").get();
    assert.equal(lock.get("immutable"), true);
  });

  await t.test("Choose My Driver transaction admits no more than three offers", async () => {
    const ids = ["choose-driver-a", "choose-driver-b", "choose-driver-c", "choose-driver-d"];
    await Promise.all(ids.map((id) => seedDriver(db, id)));
    await createScheduledRideRequestForUser("rider-choose", requestInput("choose-request-01", "chooseDriver", maximum), now);
    const results = await Promise.allSettled(ids.map((id) => respondToScheduledRideForUser(id, { requestId: "choose-request-01" })));
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 3);
    const snapshot = await db.collection("scheduledRideRequests").doc("choose-request-01").get();
    assert.equal(snapshot.get("activeOfferCount"), 3);
    const offers = await snapshot.ref.collection("offers").get();
    assert.equal(offers.size, 3);
    const selected = offers.docs[0].id;
    const result = await selectScheduledRideOfferForUser("rider-choose", { requestId: "choose-request-01", offerId: selected });
    assert.equal(result.status, "confirmed");
  });

  await t.test("schedule locks reject an overlapping assignment", async () => {
    const assigned = (await db.collection("scheduledRideRequests").doc("quick-request-001").get()).get("assignedDriverId");
    await createScheduledRideRequestForUser("rider-conflict", requestInput("conflict-req-001", "quick", maximum), now);
    await assert.rejects(() => respondToScheduledRideForUser(assigned, { requestId: "conflict-req-001" }));
  });

  await t.test("tampered maximum and disabled feature flag are rejected", async () => {
    await assert.rejects(() => createScheduledRideRequestForUser(
      "rider-tamper",
      requestInput("tampered-req-01", "quick", maximum - 1),
      now
    ));
    await db.collection("platformConfig").doc("scheduledRides").update({ enabled: false });
    await assert.rejects(() => previewScheduledRidePriceForUser("rider-disabled", requestInput("disabled-req-01", "quick", maximum)));
    await db.collection("platformConfig").doc("scheduledRides").update({ enabled: true });
  });

  await t.test("rules expose only authorized reads and deny all client mutations", async () => {
    const rules = fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8");
    const env = await initializeTestEnvironment({
      projectId,
      firestore: { host: "127.0.0.1", port: Number(process.env.FIRESTORE_EMULATOR_PORT || 8080), rules }
    });
    try {
      const riderDb = env.authenticatedContext("rider-quick").firestore();
      const strangerDb = env.authenticatedContext("stranger").firestore();
      const driverDb = env.authenticatedContext("quick-driver-a").firestore();
      await assertSucceeds(getDoc(doc(riderDb, "scheduledRideRequests/quick-request-001")));
      await assertFails(getDoc(doc(strangerDb, "scheduledRideRequests/quick-request-001")));
      await assertSucceeds(getDoc(doc(driverDb, "scheduledRideOpportunities/quick-request-001")));
      await assertSucceeds(getDoc(doc(riderDb, "scheduledRideRequests/quick-request-001/priceLocks/v1")));
      await assertSucceeds(getDoc(doc(driverDb, "drivers/quick-driver-a/scheduledRideLocks/any-bucket")));
      await assertFails(getDoc(doc(strangerDb, "drivers/quick-driver-a/scheduledRideLocks/any-bucket")));
      await assertFails(setDoc(doc(riderDb, "scheduledRideRequests/client-created"), { riderId: "rider-quick", status: "confirmed" }));
      await assertFails(setDoc(doc(driverDb, "scheduledRideRequests/quick-request-001/offers/client"), { driverId: "quick-driver-a" }));
      await assertFails(setDoc(doc(riderDb, "scheduledRideRequests/quick-request-001/priceLocks/v1"), { lockedBaseFareCents: 1 }, { merge: true }));
      await assertFails(setDoc(doc(driverDb, "drivers/quick-driver-a/scheduledRideLocks/client"), { requestId: "fake" }));
    } finally {
      await env.cleanup();
    }
  });
});
