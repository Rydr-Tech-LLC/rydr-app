const { admin, getFirestore } = require("../config/firebase");

const ACTIVE_STATUSES = new Set(["accepted", "enRouteToPickup", "navigatingToPickup", "arrivedAtPickup", "inProgress", "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"]);

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function millis(value) {
  if (!value) return Number.MAX_SAFE_INTEGER;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (Number.isFinite(value?._seconds)) return value._seconds * 1000;
  if (Number.isFinite(value?.seconds)) return value.seconds * 1000;
  return Number.MAX_SAFE_INTEGER;
}

function queuedCandidates(documents) {
  return documents
    .filter((doc) => doc.data().driverQueueStatus === "queued" && doc.data().status === "accepted")
    .sort((a, b) => {
      const left = a.data();
      const right = b.data();
      return millis(left.queuedAt ?? left.acceptedAt ?? left.createdAt) - millis(right.queuedAt ?? right.acceptedAt ?? right.createdAt)
        || a.id.localeCompare(b.id);
    });
}

async function promoteNextQueuedRide({ driverId, requestId, db = getFirestore() }) {
  if (!requestId || !/^[A-Za-z0-9_-]{8,80}$/.test(requestId)) throw error("requestId is required", 400);
  return db.runTransaction(async (tx) => {
    // Selection and promotion belong to one transaction so a concurrent
    // lifecycle update cannot create two active rides for the same driver.
    const snapshot = await tx.get(db.collection("rides").where("driverId", "==", driverId).limit(100));
    const docs = snapshot.docs;
    const duplicate = docs.find((doc) => doc.data().lastQueuePromotionRequestId === requestId);
    if (duplicate) {
      return { promoted: true, rideId: duplicate.id, status: duplicate.data().status, duplicate: true };
    }
    const active = docs.find((doc) => ACTIVE_STATUSES.has(doc.data().status) && doc.data().driverQueueStatus !== "queued");
    if (active) throw error("Driver still has an active ride", 409);
    const candidate = queuedCandidates(docs)[0];
    if (!candidate) return { promoted: false, rideId: null, status: null };
    const ride = candidate.data();
    const requestRef = db.collection("rideRequests").doc(candidate.id);
    const now = admin.firestore.Timestamp.now();
    const update = {
      driverQueueStatus: "active",
      activeAt: now,
      queuedRideStartedAt: now,
      riderStatusMessage: "Your driver is on the way.",
      queuePromotionOwner: "backend",
      lastQueuePromotionRequestId: requestId,
      updatedAt: now
    };
    tx.set(candidate.ref, update, { merge: true });
    tx.set(requestRef, update, { merge: true });
    return { promoted: true, rideId: candidate.id, status: ride.status, duplicate: false };
  });
}

module.exports = { promoteNextQueuedRide, queuedCandidates, ACTIVE_STATUSES };
