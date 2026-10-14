import { removeDriverVehicle } from "./driverVehicleArchivePolicy";
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
  try { await removeDriverVehicle({ db, FieldValue, uid, vehicleId, expectedVin, expectedPlate }); }
  catch (error: any) { throw new HttpsError(error.code ?? "internal", error.message ?? "Vehicle removal failed."); }
}
