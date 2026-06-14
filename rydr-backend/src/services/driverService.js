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

  // TODO: Feed this event into production billing/ledger logic on the backend.
  // The iOS client reports lifecycle state only and must not be trusted for final fare calculation.

  return ref.id;
}

async function createAccountDeletionRequest(payload) {
  const uid = cleanString(payload.uid);

  if (!uid) {
    throw validationError("uid is required");
  }

  const db = getFirestore();
  const ref = db.collection("accountDeletionRequests").doc();
  const request = {
    uid,
    role: cleanOptionalString(payload.role) || "driver",
    email: cleanOptionalString(payload.email) || null,
    reason: cleanOptionalString(payload.reason) || null,
    status: "requested",
    source: "driver_app",
    clientRequestedAt: cleanOptionalString(payload.requestedAt) || null,
    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  await ref.set(request);

  // TODO: Implement production deletion workflow:
  // Firebase Auth deletion, Firestore cleanup/anonymization, legally allowed Stripe cleanup,
  // required financial/legal retention, and confirmation email.

  return ref.id;
}

module.exports = {
  recordWaitTimeEvent,
  createAccountDeletionRequest
};
