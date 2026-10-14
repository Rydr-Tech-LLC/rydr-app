import { createHash } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../admin";

function identity(vehicle: any): string {
  const vin = String(vehicle?.vin ?? "").trim().toUpperCase();
  return vin || String(vehicle?.plate ?? "").replace(/[^A-Z0-9]/gi, "").toUpperCase();
}
export async function addSavedDriverVehicle(uid: string, vehicle: Record<string, any>, extra: Record<string, any>) {
  const key = identity(vehicle);
  if (!key) throw new HttpsError("invalid-argument", "A vehicle VIN or plate is required.");
  const vehicleId = createHash("sha256").update(key).digest("hex").slice(0, 24);
  const ref = db.collection("drivers").doc(uid);
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Driver profile not found.");
    const driver = snap.data()!;
    const saved = { ...(driver.savedVehicles ?? {}) };
    if (identity(driver.vehicle) === key || Object.values(saved).some(v => identity(v) === key)) {
      throw new HttpsError("already-exists", "This vehicle is already on your account.");
    }
    if (Object.keys(saved).length >= 10) throw new HttpsError("resource-exhausted", "Remove a saved vehicle before adding another.");
    saved[vehicleId] = { ...vehicle, ...extra, vehicleId, status: "saved", documentsStatus: "required", createdAt: FieldValue.serverTimestamp() };
    tx.update(ref, { savedVehicles: saved, updatedAt: FieldValue.serverTimestamp() });
  });
  return vehicleId;
}

export async function deleteSavedDriverVehicle(uid: string, vehicleId: string, expectedVin?: string, expectedPlate?: string) {
  if (vehicleId !== "current" && !/^[a-f0-9]{24}$/.test(vehicleId)) throw new HttpsError("invalid-argument", "Invalid vehicle identifier.");
  const ref = db.collection("drivers").doc(uid);
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Driver profile not found.");
    const driver = snap.data()!;
    if (vehicleId !== "current") {
      const saved = { ...(driver.savedVehicles ?? {}) };
      if (!saved[vehicleId]) throw new HttpsError("not-found", "Vehicle is no longer on your account.");
      delete saved[vehicleId];
      tx.update(ref, { savedVehicles: saved, updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    if (!driver.vehicle || identity(driver.vehicle) !== identity({ vin: expectedVin, plate: expectedPlate })) {
      throw new HttpsError("failed-precondition", "Your current vehicle changed. Refresh and try again.");
    }
    const statusRef = db.collection("driver_status").doc(uid);
    const status = (await tx.get(statusRef)).data() ?? {};
    const rides = await tx.get(db.collection("rides").where("driverId", "==", uid));
    const active = new Set(["accepted", "enRouteToPickup", "navigatingToPickup", "arrivedAtPickup", "inProgress", "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"]);
    if (driver.isOnline || driver.online || status.isOnline || status.online || driver.hasActiveRide || status.hasActiveRide || rides.docs.some(ride => active.has(ride.data().status))) {
      throw new HttpsError("failed-precondition", "Go offline and finish all assigned rides before deleting your current vehicle.");
    }
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
