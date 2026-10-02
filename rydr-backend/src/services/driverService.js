const { admin, getFirestore } = require("../config/firebase");

const WAIT_STAGES = new Set([
  "pickup_grace_started",
  "pickup_paid_started",
  "stop_paid_started",
  "wait_ended"
]);

function cleanString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function cleanOptionalString(value) {
  const cleaned = cleanString(value);
  return cleaned.length > 0 ? cleaned : undefined;
}

function cleanNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : fallback;
}

function validationError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

async function recordWaitTimeEvent(payload) {
  const rideId = cleanString(payload.rideId);
  const driverId = cleanString(payload.driverId);
  const waitStage = cleanString(payload.waitStage);

  if (!rideId) {
    throw validationError("rideId is required");
  }

  if (!driverId) {
    throw validationError("driverId is required");
  }

  if (!WAIT_STAGES.has(waitStage)) {
    throw validationError("waitStage is invalid");
  }

  const db = getFirestore();
  const ref = db.collection("waitTimeEvents").doc();
  const event = {
    rideId,
    driverId,
    waitStage,
    riderId: cleanOptionalString(payload.riderId) || null,
    complimentarySeconds: cleanNumber(payload.complimentarySeconds),
    paidWaitSeconds: cleanNumber(payload.paidWaitSeconds),
    clientTimestamp: cleanOptionalString(payload.timestamp) || null,
    source: "driver_app",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  await ref.set(event);

  // This is audit/presentation telemetry only. Financial calculation uses the
  // backend-authored lifecycle timestamps on the ride document, never these
  // client-reported durations.

  return ref.id;
}

module.exports = {
  recordWaitTimeEvent
};
