const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds
} = require("@firebase/rules-unit-testing");
const {
  collection,
  collectionGroup,
  doc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where
} = require("firebase/firestore");

const projectId = "rydr-rules-test";
let environment;

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_PORT || 8080),
      rules: fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8")
    }
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "betaInvites/rider/phones/+16783220004"), { status: "approved" });
    await setDoc(doc(db, "betaInvites/driver/phones/+16783225555"), { status: "approved" });
    await setDoc(doc(db, "riders/rider-1"), { uid: "rider-1", preferredName: "Rider", hasRydrRiderAccess: true });
    await setDoc(doc(db, "drivers/driver-1"), {
      uid: "driver-1",
      displayName: "Driver",
      selectedRideTypes: ["Rydr Go"],
      vehicle: { make: "Toyota", model: "Camry", year: 2025, plate: "SAFE1" }
    });
    await setDoc(doc(db, "scheduledRideRequests/request-1"), {
      riderId: "rider-1",
      assignedDriverId: null,
      status: "matching"
    });
    await setDoc(doc(db, "scheduledRideRequests/request-1/opportunities/driver-1"), {
      driverId: "driver-1",
      status: "available"
    });
    await setDoc(doc(db, "scheduledRideRequests/request-1/opportunities/driver-2"), {
      driverId: "driver-2",
      status: "available"
    });
    await setDoc(doc(db, "scheduledRideRequests/request-1/offers/driver-1"), {
      driverId: "driver-1",
      status: "available"
    });
    await setDoc(doc(db, "scheduledRideRequests/request-1/offers/driver-2"), {
      driverId: "driver-2",
      status: "available"
    });
    await setDoc(doc(db, "scheduledRideRequests/request-2"), {
      riderId: "rider-1",
      assignedDriverId: "driver-1",
      status: "confirmed"
    });
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test("rider may edit personal profile fields but not grant access", async () => {
  const db = environment.authenticatedContext("rider-1", { phone_number: "+16783220004" }).firestore();
  await assertSucceeds(updateDoc(doc(db, "riders/rider-1"), { preferredName: "Khris" }));
  await assertFails(updateDoc(doc(db, "riders/rider-1"), { hasRydrRiderAccess: false }));
  await assertFails(updateDoc(doc(db, "riders/rider-1"), { cashHubRole: "driver" }));
});

test("driver may edit dispatch preferences but not canonical vehicle or documents", async () => {
  const db = environment.authenticatedContext("driver-1", { phone_number: "+16783225555" }).firestore();
  await assertSucceeds(updateDoc(doc(db, "drivers/driver-1"), { selectedRideTypes: ["Rydr Go", "Rydr XL"] }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { vehicle: { make: "Bentley", model: "Flying Spur", year: 2026 } }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { documents: { insurance: { status: "approved" } } }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { identityVerificationStepCompleted: true }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { payoutsStepCompleted: true }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { driverSignupCompleted: true }));
});

test("mobile clients cannot create authoritative ride records", async () => {
  const db = environment.authenticatedContext("rider-1", { phone_number: "+16783220004" }).firestore();
  await assertFails(setDoc(doc(db, "rideRequests/ride-1"), { riderId: "rider-1", status: "pending" }));
  await assertFails(setDoc(doc(db, "rideRequestSignals/ride-1"), { riderId: "rider-1", status: "pending" }));
  await assertFails(setDoc(doc(db, "rides/ride-1"), { riderId: "rider-1", status: "pending" }));
});

test("driver may query only their own scheduled ride opportunities", async () => {
  const db = environment.authenticatedContext("driver-1", { phone_number: "+16783225555" }).firestore();
  const ownOpportunities = query(
    collectionGroup(db, "opportunities"),
    where("driverId", "==", "driver-1"),
    where("status", "==", "available")
  );
  const otherOpportunities = query(
    collectionGroup(db, "opportunities"),
    where("driverId", "==", "driver-2"),
    where("status", "==", "available")
  );

  const snapshot = await assertSucceeds(getDocs(ownOpportunities));
  assert.equal(snapshot.size, 1);
  await assertFails(getDocs(otherOpportunities));
});

test("driver may query only their own pending scheduled driver selections", async () => {
  const db = environment.authenticatedContext("driver-1", { phone_number: "+16783225555" }).firestore();
  const ownOffers = query(
    collectionGroup(db, "offers"),
    where("driverId", "==", "driver-1"),
    where("status", "==", "available")
  );
  const otherOffers = query(
    collectionGroup(db, "offers"),
    where("driverId", "==", "driver-2"),
    where("status", "==", "available")
  );

  const snapshot = await assertSucceeds(getDocs(ownOffers));
  assert.equal(snapshot.size, 1);
  await assertFails(getDocs(otherOffers));
});

test("driver may query their own scheduled assignments", async () => {
  const db = environment.authenticatedContext("driver-1", { phone_number: "+16783225555" }).firestore();
  const assignments = query(
    collection(db, "scheduledRideRequests"),
    where("assignedDriverId", "==", "driver-1")
  );

  const snapshot = await assertSucceeds(getDocs(assignments));
  assert.equal(snapshot.size, 1);
});

test("admin clients can manage rides but canonical profile fields remain service-only", async () => {
  const db = environment.authenticatedContext("admin-1", { admin: true, role: "admin" }).firestore();
  await assertSucceeds(setDoc(doc(db, "rides/admin-created"), { riderId: "rider-1", status: "pending" }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { vehicle: { make: "Toyota", model: "Camry", year: 2026 } }));
});
