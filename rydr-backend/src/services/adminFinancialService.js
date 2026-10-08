const { admin, getFirestore } = require("../config/firebase");

const ACTIONS = {
  resolve: { paymentStatus: "paid_externally", resolutionType: "paid_externally" },
  write_off: { paymentStatus: "written_off", resolutionType: "written_off" }
};

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

async function resolvePaymentFailure({ rideId, action, adminUid, reason, requestId, db = getFirestore() }) {
  const policy = ACTIONS[action];
  if (!policy) throw error("Invalid payment resolution action", 400);
  if (!adminUid || !/^[A-Za-z0-9:_-]{1,128}$/.test(adminUid)) throw error("A valid adminUid is required", 400);
  if (!requestId || !/^[A-Za-z0-9_-]{8,100}$/.test(requestId)) throw error("requestId is required", 400);
  const rideRef = db.collection("rides").doc(rideId);
  const jobRef = db.collection("paymentJobs").doc(rideId);
  return db.runTransaction(async (tx) => {
    const [rideSnap, jobSnap] = await Promise.all([tx.get(rideRef), tx.get(jobRef)]);
    if (!rideSnap.exists) throw error("Ride not found", 404);
    const ride = rideSnap.data();
    if (ride.lastAdminPaymentResolutionRequestId === requestId) {
      return { duplicate: true, paymentStatus: ride.paymentStatus, resolutionType: ride.adminResolutionType };
    }
    if (ride.paymentStatus !== "failed") throw error("Only a failed payment may be resolved manually", 409);
    const now = admin.firestore.Timestamp.now();
    tx.set(rideRef, {
      paymentStatus: policy.paymentStatus,
      adminResolutionType: policy.resolutionType,
      adminResolutionNote: typeof reason === "string" ? reason.trim().slice(0, 500) : null,
      adminResolvedBy: adminUid,
      adminResolvedAt: now,
      lastAdminPaymentResolutionRequestId: requestId,
      updatedAt: now
    }, { merge: true });
    tx.set(jobRef, {
      rideId,
      status: "resolved",
      resolutionType: policy.resolutionType,
      resolvedBy: adminUid,
      resolvedAt: now,
      updatedAt: now,
      ...(jobSnap.exists ? {} : { createdAt: now })
    }, { merge: true });
    return { duplicate: false, paymentStatus: policy.paymentStatus, resolutionType: policy.resolutionType };
  });
}

module.exports = { resolvePaymentFailure, ACTIONS };
