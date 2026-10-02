const { admin, getFirestore } = require("../config/firebase");

const MAX_REASON_LENGTH = 1000;
const ACTIVE_REQUEST_STATUSES = new Set(["requested", "processing"]);

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function normalizeReason(value) {
  if (value == null) return null;
  if (typeof value !== "string") throw error("reason must be a string", 400);
  const reason = value.trim();
  if (reason.length > MAX_REASON_LENGTH) {
    throw error(`reason must be ${MAX_REASON_LENGTH} characters or fewer`, 400);
  }
  return reason || null;
}

function rolesForProfiles(riderExists, driverExists) {
  const roles = [];
  if (riderExists) roles.push("rider");
  if (driverExists) roles.push("driver");
  return roles;
}

async function createAccountDeletionRequest({
  uid,
  reason,
  tokenEmail,
  db = getFirestore()
}) {
  if (!uid || typeof uid !== "string") throw error("Authenticated uid is required", 401);
  const cleanReason = normalizeReason(reason);

  const riderRef = db.collection("riders").doc(uid);
  const driverRef = db.collection("drivers").doc(uid);
  const statusRef = db.collection("driver_status").doc(uid);
  const publicDriverRef = db.collection("publicDriverProfiles").doc(uid);
  const requestRef = db.collection("accountDeletionRequests").doc(uid);

  const result = await db.runTransaction(async (tx) => {
    const [riderSnap, driverSnap, statusSnap, publicDriverSnap, existingSnap] = await Promise.all([
      tx.get(riderRef),
      tx.get(driverRef),
      tx.get(statusRef),
      tx.get(publicDriverRef),
      tx.get(requestRef)
    ]);

    const roles = rolesForProfiles(riderSnap.exists, driverSnap.exists);
    if (roles.length === 0) throw error("No Rider or Driver profile exists for this account", 404);

    const existing = existingSnap.exists ? existingSnap.data() : null;
    if (existing && ACTIVE_REQUEST_STATUSES.has(existing.status)) {
      return {
        requestId: uid,
        status: existing.status,
        roles: Array.isArray(existing.roles) ? existing.roles : roles,
        duplicate: true
      };
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const rider = riderSnap.exists ? riderSnap.data() : {};
    const driver = driverSnap.exists ? driverSnap.data() : {};
    const email = typeof tokenEmail === "string" && tokenEmail.trim()
      ? tokenEmail.trim()
      : (rider.email || driver.email || null);
    const primaryRole = roles.includes("driver") ? "driver" : "rider";
    const request = {
      uid,
      userId: uid,
      role: primaryRole,
      roles,
      email,
      reason: cleanReason,
      status: "requested",
      source: "rydr_backend",
      priorAccountStatuses: {
        ...(riderSnap.exists ? { rider: rider.accountStatus ?? null } : {}),
        ...(driverSnap.exists ? { driver: driver.accountStatus ?? null } : {})
      },
      processedAt: admin.firestore.FieldValue.delete(),
      processedBy: admin.firestore.FieldValue.delete(),
      rejectionReason: admin.firestore.FieldValue.delete(),
      requestedAt: now,
      updatedAt: now
    };
    if (!existingSnap.exists) request.createdAt = now;
    tx.set(requestRef, request, { merge: true });

    const profileUpdate = {
      accountStatus: "deletion_requested",
      accountDeletionStatus: "requested",
      accountDeletionRequestedAt: now,
      updatedAt: now
    };
    if (riderSnap.exists) tx.set(riderRef, profileUpdate, { merge: true });
    if (driverSnap.exists) {
      tx.set(driverRef, {
        ...profileUpdate,
        online: false,
        isOnline: false,
        availabilityStatus: "offline"
      }, { merge: true });
      if (statusSnap.exists) {
        tx.set(statusRef, {
          online: false,
          isOnline: false,
          availabilityStatus: "offline",
          updatedAt: now
        }, { merge: true });
      }
      if (publicDriverSnap.exists) {
        tx.set(publicDriverRef, {
          isOnline: false,
          availabilityStatus: "offline",
          updatedAt: now
        }, { merge: true });
      }
    }

    return { requestId: uid, status: "requested", roles, duplicate: false };
  });

  return result;
}

module.exports = {
  MAX_REASON_LENGTH,
  createAccountDeletionRequest,
  normalizeReason,
  rolesForProfiles
};
