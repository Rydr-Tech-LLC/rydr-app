const { admin, getFirestore, getStorageBucketsForReads } = require("../config/firebase");

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function text(value, maxLength) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function documentPath(uid, kind, value) {
  const path = text(value, 500);
  const prefix = `driverDocuments/${uid}/${kind}/`;
  if (!path.startsWith(prefix) || !/\.(jpe?g|png|heic)$/i.test(path)) {
    throw error(`A valid ${kind} upload owned by this driver is required`, 400);
  }
  return path;
}

async function requireStoredUploads(paths, buckets = getStorageBucketsForReads()) {
  for (const path of paths) {
    let exists = false;
    for (const bucket of buckets) {
      const [found] = await bucket.file(path).exists().catch(() => [false]);
      if (found) {
        exists = true;
        break;
      }
    }
    if (!exists) throw error("An uploaded driver document could not be verified", 409);
  }
}

async function prepareDriverLicense({ uid, payload, db = getFirestore() }) {
  const number = text(payload?.licenseNumber, 40);
  const state = text(payload?.licenseState, 20).toUpperCase();
  if (!number || !state) throw error("License number and state are required", 400);
  await db.collection("drivers").doc(uid).set({
    license: { number, state },
    licensePreparedAt: admin.firestore.Timestamp.now(),
    updatedAt: admin.firestore.Timestamp.now()
  }, { merge: true });
  return { prepared: true };
}

async function finalizeDriverDocuments({ uid, kind, payload, db = getFirestore(), storageBuckets }) {
  const driverRef = db.collection("drivers").doc(uid);
  const now = admin.firestore.Timestamp.now();
  if (kind === "license") {
    const frontStoragePath = documentPath(uid, "driverLicense", payload?.frontStoragePath);
    const backStoragePath = documentPath(uid, "driverLicense", payload?.backStoragePath);
    await requireStoredUploads([frontStoragePath, backStoragePath], storageBuckets);
    await driverRef.set({
      licenseStepCompleted: true,
      licensePhotosSelected: true,
      licenseSubmission: { frontStoragePath, backStoragePath, submittedAt: now },
      updatedAt: now
    }, { merge: true });
    return { kind, completed: true };
  }
  if (kind === "vehicle") {
    const plate = text(payload?.plate, 20).toUpperCase();
    if (!plate) throw error("A vehicle plate is required", 400);
    const registrationStoragePath = documentPath(uid, "registration", payload?.registrationStoragePath);
    const insuranceStoragePath = documentPath(uid, "insurance", payload?.insuranceStoragePath);
    await requireStoredUploads([registrationStoragePath, insuranceStoragePath], storageBuckets);
    const driverSnap = await driverRef.get();
    const vehicle = driverSnap.data()?.vehicle || {};
    if (!text(vehicle.make, 80) || !text(vehicle.model, 80) || !Number.isFinite(Number(vehicle.year))) {
      throw error("Submit the vehicle to backend eligibility before attaching documents", 409);
    }
    await driverRef.update({
      "vehicle.plate": plate,
      vehicleStepCompleted: true,
      registrationDocumentSelected: true,
      insuranceDocumentSelected: true,
      vehicleDocumentSubmission: { registrationStoragePath, insuranceStoragePath, submittedAt: now },
      updatedAt: now
    });
    return { kind, completed: true, plate };
  }
  throw error("Unsupported driver document finalization kind", 400);
}

async function updateVehiclePlate({ uid, plate, db = getFirestore() }) {
  const normalizedPlate = text(plate, 20).toUpperCase();
  if (!normalizedPlate) throw error("A vehicle plate is required", 400);
  const ref = db.collection("drivers").doc(uid);
  const snap = await ref.get();
  const vehicle = snap.data()?.vehicle || {};
  if (!snap.exists || !text(vehicle.make, 80) || !text(vehicle.model, 80)) {
    throw error("A backend-verified vehicle is required", 409);
  }
  await ref.update({ "vehicle.plate": normalizedPlate, updatedAt: admin.firestore.Timestamp.now() });
  return { plate: normalizedPlate };
}

module.exports = {
  prepareDriverLicense,
  finalizeDriverDocuments,
  updateVehiclePlate,
  documentPath,
  requireStoredUploads
};
