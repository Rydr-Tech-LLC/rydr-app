const { randomUUID } = require("crypto");
function failure(code, message) { const error = new Error(message); error.code = code; return error; }
function identity(vehicle) {
  const vin = String(vehicle?.vin ?? "").trim().toUpperCase();
  return vin || String(vehicle?.plate ?? "").replace(/[^A-Z0-9]/gi, "").toUpperCase();
}
/** @param {any} options */
async function removeDriverVehicle({ db, FieldValue, uid, vehicleId, expectedVin, expectedPlate, actorUid = uid, actorRole = "driver", reason = "Removed in driver app" }) {
  const archiveId = randomUUID();
  if (vehicleId !== "current" && !/^[a-f0-9]{24}$/.test(vehicleId)) throw failure("invalid-argument", "Invalid vehicle identifier.");
  const ref = db.collection("drivers").doc(uid);
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw failure("not-found", "Driver profile not found.");
    const driver = snap.data();
    if (vehicleId !== "current") {
      const saved = { ...(driver.savedVehicles ?? {}) };
      if (!saved[vehicleId]) throw failure("not-found", "Vehicle is no longer on your account.");
      tx.set(ref.collection("vehicleArchive").doc(archiveId), { driverUid: uid, vehicleId, vehicle: saved[vehicleId], action: "removed", actorUid, actorRole, reason, recordedAt: FieldValue.serverTimestamp() });
      delete saved[vehicleId];
      tx.update(ref, { savedVehicles: saved, updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    if (!driver.vehicle || identity(driver.vehicle) !== identity({ vin: expectedVin, plate: expectedPlate })) {
      throw failure("failed-precondition", "Your current vehicle changed. Refresh and try again.");
    }
    const statusRef = db.collection("driver_status").doc(uid);
    const status = (await tx.get(statusRef)).data() ?? {};
    const rides = await tx.get(db.collection("rides").where("driverId", "==", uid));
    const active = new Set(["accepted", "enRouteToPickup", "navigatingToPickup", "arrivedAtPickup", "inProgress", "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"]);
    if (driver.isOnline || driver.online || status.isOnline || status.online || driver.hasActiveRide || status.hasActiveRide || rides.docs.some(ride => active.has(ride.data().status))) {
      throw failure("failed-precondition", "Go offline and finish all assigned rides before deleting your current vehicle.");
    }
    tx.set(ref.collection("vehicleArchive").doc(archiveId), { driverUid: uid, vehicleId, vehicle: driver.vehicle, documents: { registration: driver.documents?.registration ?? null, insurance: driver.documents?.insurance ?? null }, action: "removed", actorUid, actorRole, reason, recordedAt: FieldValue.serverTimestamp() });
    tx.update(ref, {
      vehicle: FieldValue.delete(), vehicleEligibility: FieldValue.delete(),
      vehicleDocumentSubmission: FieldValue.delete(), "documents.registration": FieldValue.delete(), "documents.insurance": FieldValue.delete(),
      registrationStatus: "missing", insuranceStatus: "missing", vehicleStepCompleted: false,
      qualifiedRideTypes: [], supportedRideTypes: [], selectedRideTypes: [], rideTypes: [],
      driverApprovalStatus: "needs_attention", isApproved: false, canGoOnline: false, isOnline: false, online: false,
      vehicleImageStatus: "missing", updatedAt: FieldValue.serverTimestamp()
    });
    const projection = { vehicle: FieldValue.delete(), isOnline: false, online: false, canGoOnline: false, availabilityStatus: "offline", selectedRideTypes: [], rideTypes: [], updatedAt: FieldValue.serverTimestamp() };
    for (const name of ["driver_status", "publicDriverProfiles", "cashHubDriverProfiles"]) tx.set(db.collection(name).doc(uid), projection, { merge: true });
  });
}

module.exports = { removeDriverVehicle };
