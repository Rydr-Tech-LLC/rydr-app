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
  getDoc,
  Timestamp,
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
    await setDoc(doc(db, "operationalSecurity/liveBetaAccess"), {configured:true,blockedAuthUids:["rider-1","rider-2","driver-1","driver-2","attacker","other","stranger","compliance-driver"],testPhoneNumbers:["+16783220004","+16783225555"]});
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


test("mobile clients cannot forge mode-specific Stripe account or verification state", async () => {
  for (const [collectionName, uid] of [["riders", "rider-1"], ["drivers", "driver-1"]]) {
    const db = environment.authenticatedContext(uid).firestore();
    await assertFails(updateDoc(doc(db, collectionName, uid), { stripeMode: "live" }));
    await assertFails(updateDoc(doc(db, collectionName, uid), {
      stripeProfiles: { live: { stripeAccountId: "acct_forged", identityVerified: true } }
    }));
  }
});

test("drivers cannot self-approve premium verification or forge public qualification", async () => {
  const db = environment.authenticatedContext("driver-1", { phone_number: "+16783225555" }).firestore();
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { premiumReview: { luxuryVehicleApproved: true } }));
  await assertFails(updateDoc(doc(db, "drivers/driver-1"), { premiumServiceHold: false }));
  await assertFails(setDoc(doc(db, "publicDriverProfiles/driver-1"), { uid: "driver-1", premiumEligibility: { executive: { eligible: true } } }, { merge: true }));
});

test("drivers cannot clear compliance holds or forge verified screening", async () => {
  const db = environment.authenticatedContext("driver-1").firestore();
  for (const field of ["documentComplianceHold", "backgroundCheckHold", "documentComplianceVerified", "documentComplianceDeadlines", "backgroundScreening", "complianceRequirements"]) {
    await assertFails(updateDoc(doc(db, "drivers/driver-1"), { [field]: false }));
  }
});
test("marketplace access rejects expired documents and beta screening bypass after pilot gate", async () => {
  const uid = "compliance-driver";
  const future = Timestamp.fromMillis(Date.now() + 86400000);
  const profile = { isApproved: true, driverApprovalStatus: "approved", cashHubTermsAccepted: true, cashHubTermsVersion: "fixture-v1", documentComplianceVerified: { driverLicense: true, insurance: true, registration: true }, documentComplianceDeadlines: { driverLicense: future, insurance: future, registration: future } };
  const db = environment.authenticatedContext(uid).firestore();
  async function seed(policy, fields) {
    await environment.withSecurityRulesDisabled(async context => {
      const admin = context.firestore();
      await setDoc(doc(admin, "platformConfig/cashRydrHub"), { cashHubTermsVersion: "fixture-v1" });
      await setDoc(doc(admin, "platformConfig/driverCompliance"), policy);
      await setDoc(doc(admin, `drivers/${uid}`), { ...profile, ...fields });
      await setDoc(doc(admin, "cashHubDriverProfiles/example"), { uid: "example" });
    });
  }
  await seed({}, {});
  await assertSucceeds(getDoc(doc(db, "cashHubDriverProfiles/example")));
  await seed({}, { documentComplianceDeadlines: { ...profile.documentComplianceDeadlines, insurance: Timestamp.fromMillis(Date.now() - 1000) } });
  await assertFails(getDoc(doc(db, "cashHubDriverProfiles/example")));
  await seed({ backgroundChecksRequired: true }, { betaBackgroundCheckBypassEnabled: true });
  await assertFails(getDoc(doc(db, "cashHubDriverProfiles/example")));
  await seed({ backgroundChecksRequired: true }, { backgroundScreening: { status: "passed", reviewedBy: "admin", reportReference: "provider/report", requirementVersion: "open-pilot-v1", validUntil: future } });
  await assertSucceeds(getDoc(doc(db, "cashHubDriverProfiles/example")));
});

test("vehicle security archive is readable only by admin and cannot be changed by clients", async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "drivers/driver-1/vehicleArchive/record-1"), { vehicle: { vin: "fixture", plate: "SAFE1" }, action: "removed" });
  });
  const driver = environment.authenticatedContext("driver-1").firestore();
  const admin = environment.authenticatedContext("admin-1", { admin: true }).firestore();
  const archivePath = "drivers/driver-1/vehicleArchive/record-1";
  await assertFails(getDoc(doc(driver, archivePath)));
  await assertSucceeds(getDoc(doc(admin, archivePath)));
  await assertFails(updateDoc(doc(driver, archivePath), { action: "edited" }));
  await assertFails(updateDoc(doc(admin, archivePath), { action: "edited" }));
});

test('promotion codes, financial rewards and eligibility counters are server-owned', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const db=context.firestore();
    await setDoc(doc(db,'promotions/private-campaign'),{schemaVersion:2,status:'active',title:'Private',audienceUserIds:['rider-1']});
    await setDoc(doc(db,'promotionCodes/PRIVATE'),{promotionId:'private-campaign'});
    await setDoc(doc(db,'promotionRewards/reward-1'),{userId:'rider-1',status:'available'});
    await setDoc(doc(db,'promotionProgress/progress-1'),{userId:'rider-1',eligibleRideCount:1});
  });
  const owner=environment.authenticatedContext('rider-1').firestore();
  const other=environment.authenticatedContext('rider-2').firestore();
  const admin=environment.authenticatedContext('admin-1',{admin:true}).firestore();
  await assertFails(getDoc(doc(owner,'promotionCodes/PRIVATE')));
  await assertFails(getDoc(doc(owner,'promotions/private-campaign')));
  await assertSucceeds(getDoc(doc(owner,'promotionRewards/reward-1')));
  await assertFails(getDoc(doc(other,'promotionRewards/reward-1')));
  await assertFails(updateDoc(doc(owner,'promotionProgress/progress-1'),{eligibleRideCount:99}));
  await assertFails(updateDoc(doc(admin,'promotionRewards/reward-1'),{status:'used'}));
  await assertFails(setDoc(doc(owner,'promotionEnrollments/fake'),{userId:'rider-1',promotionId:'private-campaign'}));
});

test('real identities cannot read or create Test profiles even when they own the UID',async()=>{
 const db=environment.authenticatedContext('real-beta',{phone_number:'+15555550999'}).firestore();
 await assertFails(getDoc(doc(db,'riders/real-beta')));
 await assertFails(setDoc(doc(db,'riders/real-beta'),{uid:'real-beta',preferredName:'Real'}));
});
test('a recreated Firebase test-number identity is routed to Test without an allowlisted UID',async()=>{
 const db=environment.authenticatedContext('recreated-test',{phone_number:'+16783220004'}).firestore();
 await assertSucceeds(getDoc(doc(db,'riders/recreated-test')));
 await assertFails(getDoc(doc(db,'operationalSecurity/liveBetaAccess')));
});

test("separated Test project authorizes its own identities without phone-based routing", async () => {
  let original;
  await environment.withSecurityRulesDisabled(async context => {
    const ref = doc(context.firestore(), "operationalSecurity/liveBetaAccess");
    original = (await getDoc(ref)).data();
    await setDoc(ref, {...original, version:2, authSeparationEnabled:true, workspaceId:"test"});
  });
  try {
    const db = environment.authenticatedContext("new-test-identity", {phone_number:"+16783220004"}).firestore();
    await assertSucceeds(getDoc(doc(db,"riders/new-test-identity")));
    await assertFails(getDoc(doc(db,"riders/rider-1")));
  } finally {
    await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(),"operationalSecurity/liveBetaAccess"), original));
  }
});

test("the original control database denies end-user access after Auth separation", async () => {
  let original;
  await environment.withSecurityRulesDisabled(async context => {
    const ref = doc(context.firestore(), "operationalSecurity/liveBetaAccess");
    original = (await getDoc(ref)).data();
    await setDoc(ref, {...original, version:2, authSeparationEnabled:true, workspaceId:"control"});
  });
  try {
    const user = environment.authenticatedContext("rider-1", {phone_number:"+16783220004"}).firestore();
    await assertFails(getDoc(doc(user,"riders/rider-1")));
    const staff = environment.authenticatedContext("staff", {admin:true}).firestore();
    await assertSucceeds(getDoc(doc(staff,"riders/rider-1")));
  } finally {
    await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(),"operationalSecurity/liveBetaAccess"), original));
  }
});
