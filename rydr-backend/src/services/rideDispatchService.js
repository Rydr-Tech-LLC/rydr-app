const { admin, getFirestore } = require("../config/firebase");
const { tierFor } = require("./rideFinancialService");

const OFFER_TTL_SECONDS = 18;
const MAX_CANDIDATE_HINTS = 20;

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (Number.isFinite(value?._seconds)) return value._seconds * 1000;
  if (Number.isFinite(value?.seconds)) return value.seconds * 1000;
  return null;
}

function normalizedCandidateIds(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value
    .map((item) => String(item || "").trim())
    .filter((item) => /^[A-Za-z0-9_-]{1,128}$/.test(item)))]
    .slice(0, MAX_CANDIDATE_HINTS);
}

function canonicalRideTypes(profile) {
  const values = profile?.eligibleRideTypes
    ?? profile?.selectedRideTypes
    ?? profile?.rideTypes
    ?? profile?.supportedRideTypes
    ?? [];
  return new Set((Array.isArray(values) ? values : []).map(tierFor));
}

function isEligibleCandidate(profile, rideType) {
  if (!profile || profile.isOnline !== true || profile.standardDispatchEnabled === false) return false;
  const availability = String(profile.availabilityStatus || "available");
  if (!["available", "onCurrentRide"].includes(availability)) return false;
  const types = canonicalRideTypes(profile);
  return types.size === 0 || types.has(tierFor(rideType));
}

function coordinate(value) {
  if (!value || typeof value !== "object") return null;
  const lat = Number(value.lat ?? value.latitude);
  const lng = Number(value.lng ?? value.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function distanceMiles(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY;
  const radiusMiles = 3958.7613;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const aLat = (a.lat * Math.PI) / 180;
  const bLat = (b.lat * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(aLat) * Math.cos(bLat) * Math.sin(dLng / 2) ** 2;
  return radiusMiles * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function candidateSortValue(profile, pickup) {
  const location = coordinate(profile?.approximateLocation) || coordinate(profile?.location);
  const distance = distanceMiles(location, pickup);
  const rating = Number(profile?.rating) || 0;
  return { distance, rating };
}

async function selectNextCandidate({ db, request, attemptedDriverIds }) {
  // Deja's matching service owns how this backend-created candidate pool is
  // produced. Until that integration lands, these hints come from the current
  // rider discovery response; every candidate is still revalidated here and
  // the phone cannot force an offline or ride-type-ineligible assignment.
  const hintedIds = normalizedCandidateIds(request.dispatchCandidateIds ?? request.dispatchCandidateHints)
    .filter((id) => !attemptedDriverIds.includes(id));
  if (hintedIds.length === 0) return null;

  const refs = hintedIds.map((id) => db.collection("publicDriverProfiles").doc(id));
  const snapshots = await db.getAll(...refs);
  const pickup = coordinate(request.pickupCoordinate) || coordinate(request.pickupGeoPoint);
  const candidates = snapshots
    .filter((snapshot) => snapshot.exists && isEligibleCandidate(snapshot.data(), request.rideType))
    .map((snapshot) => ({ id: snapshot.id, profile: snapshot.data() }))
    .sort((left, right) => {
      const a = candidateSortValue(left.profile, pickup);
      const b = candidateSortValue(right.profile, pickup);
      if (a.distance !== b.distance) return a.distance - b.distance;
      return b.rating - a.rating;
    });
  return candidates[0] || null;
}

function offerExpiration(now) {
  return admin.firestore.Timestamp.fromMillis(now.toMillis() + OFFER_TTL_SECONDS * 1000);
}

async function initializeRideDispatch({ rideId, uid, candidateIds, requestId, db = getFirestore() }) {
  if (!requestId || !/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) throw error("requestId is required", 400);
  const requestRef = db.collection("rideRequests").doc(rideId);
  const signalRef = db.collection("rideRequestSignals").doc(rideId);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) throw error("Ride request not found", 404);
  const request = requestSnap.data();
  if (request.riderId !== uid) throw error("Only the rider may initialize dispatch", 403);
  if (typeof request.driverId !== "string" || !request.driverId) throw error("Selected driver is required", 400);

  const hints = normalizedCandidateIds([request.driverId, ...(Array.isArray(candidateIds) ? candidateIds : [])]);
  const initialCandidateSnap = await db.collection("publicDriverProfiles").doc(request.driverId).get();
  if (!initialCandidateSnap.exists || !isEligibleCandidate(initialCandidateSnap.data(), request.rideType)) {
    throw error("The selected driver is no longer eligible", 409);
  }

  return db.runTransaction(async (tx) => {
    const current = await tx.get(requestRef);
    if (!current.exists) throw error("Ride request not found", 404);
    const data = current.data();
    if (data.riderId !== uid) throw error("Only the rider may initialize dispatch", 403);
    if (data.lastDispatchRequestId === requestId) {
      return dispatchResult(data, true);
    }
    if (data.dispatchStatus && data.dispatchStatus !== "initializing") {
      return dispatchResult(data, true);
    }
    if (data.status !== "pending") throw error("Ride request is no longer pending", 409);

    const now = admin.firestore.Timestamp.now();
    const expiresAt = offerExpiration(now);
    const update = {
      dispatchStatus: "offered",
      dispatchAttemptNumber: 1,
      dispatchCandidateIds: hints,
      attemptedDriverIds: [],
      offerCreatedAt: now,
      offerExpiresAt: expiresAt,
      lastDispatchRequestId: requestId,
      dispatchUpdatedAt: now,
      lifecycleOwner: "backend",
      updatedAt: now
    };
    tx.set(requestRef, update, { merge: true });
    tx.set(signalRef, {
      driverId: data.driverId,
      status: "pending",
      expiresAt,
      dispatchAttemptNumber: 1,
      updatedAt: now
    }, { merge: true });
    return dispatchResult({ ...data, ...update }, false);
  });
}

function dispatchResult(data, duplicate = false) {
  return {
    status: data.status,
    dispatchStatus: data.dispatchStatus || null,
    driverId: data.driverId || null,
    attemptNumber: Number(data.dispatchAttemptNumber || 0),
    offerExpiresAtMillis: timestampMillis(data.offerExpiresAt),
    attemptedDriverIds: Array.isArray(data.attemptedDriverIds) ? data.attemptedDriverIds : [],
    duplicate
  };
}

async function advanceRideDispatch({ rideId, actorUid, actorRole, reason, requestId, db = getFirestore() }) {
  if (!requestId || !/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) throw error("requestId is required", 400);
  const requestRef = db.collection("rideRequests").doc(rideId);
  const signalRef = db.collection("rideRequestSignals").doc(rideId);
  const initialSnap = await requestRef.get();
  if (!initialSnap.exists) throw error("Ride request not found", 404);
  const initial = initialSnap.data();
  const priorDrivers = Array.isArray(initial.attemptedDriverIds) ? initial.attemptedDriverIds : [];
  if (initial.lastDispatchRequestId === requestId) {
    const ownsDuplicate = actorRole === "rider"
      ? initial.riderId === actorUid
      : initial.driverId === actorUid || priorDrivers.includes(actorUid);
    if (ownsDuplicate) return dispatchResult(initial, true);
  }
  if (actorRole === "driver" && initial.driverId !== actorUid) throw error("This offer is not assigned to the driver", 403);
  if (actorRole === "rider" && initial.riderId !== actorUid) throw error("This request does not belong to the rider", 403);
  if (initial.status !== "pending") return dispatchResult(initial, false);

  const attemptedDriverIds = [...new Set([
    ...(Array.isArray(initial.attemptedDriverIds) ? initial.attemptedDriverIds : []),
    initial.driverId
  ].filter(Boolean))];
  const nextCandidate = await selectNextCandidate({ db, request: initial, attemptedDriverIds });

  return db.runTransaction(async (tx) => {
    const currentSnap = await tx.get(requestRef);
    if (!currentSnap.exists) throw error("Ride request not found", 404);
    const current = currentSnap.data();
    if (current.lastDispatchRequestId === requestId) return dispatchResult(current, true);
    if (current.status !== "pending") return dispatchResult(current, false);
    if (current.driverId !== initial.driverId) return dispatchResult(current, true);

    const now = admin.firestore.Timestamp.now();
    const attemptNumber = Number(current.dispatchAttemptNumber || 1);
    const attemptRef = requestRef.collection("dispatchAttempts").doc(String(attemptNumber).padStart(4, "0"));
    tx.set(attemptRef, {
      attemptNumber,
      driverId: current.driverId,
      outcome: reason,
      actorRole,
      actorUid,
      offeredAt: current.offerCreatedAt ?? current.createdAt ?? null,
      expiredAt: reason === "expired" || reason === "missed" ? now : null,
      endedAt: now,
      createdAt: now
    });

    if (!nextCandidate) {
      const terminal = {
        status: "noDriversAvailable",
        dispatchStatus: "noDriversAvailable",
        attemptedDriverIds,
        terminalReason: "candidate_pool_exhausted",
        lastDispatchRequestId: requestId,
        dispatchUpdatedAt: now,
        updatedAt: now
      };
      tx.set(requestRef, terminal, { merge: true });
      tx.set(signalRef, { status: "closed", expiresAt: now, updatedAt: now }, { merge: true });
      return dispatchResult({ ...current, ...terminal }, false);
    }

    const expiresAt = offerExpiration(now);
    const rematch = {
      driverId: nextCandidate.id,
      status: "pending",
      dispatchStatus: "rematching",
      dispatchAttemptNumber: attemptNumber + 1,
      attemptedDriverIds,
      offerCreatedAt: now,
      offerExpiresAt: expiresAt,
      lastDispatchRequestId: requestId,
      dispatchUpdatedAt: now,
      terminalReason: admin.firestore.FieldValue.delete(),
      updatedAt: now
    };
    tx.set(requestRef, rematch, { merge: true });
    tx.set(signalRef, {
      driverId: nextCandidate.id,
      status: "pending",
      expiresAt,
      dispatchAttemptNumber: attemptNumber + 1,
      updatedAt: now
    }, { merge: true });
    return dispatchResult({ ...current, ...rematch }, false);
  });
}

async function refreshRideDispatch({ rideId, uid, requestId, db = getFirestore(), nowMillis = Date.now() }) {
  const requestRef = db.collection("rideRequests").doc(rideId);
  const snapshot = await requestRef.get();
  if (!snapshot.exists) throw error("Ride request not found", 404);
  const request = snapshot.data();
  if (request.riderId !== uid) throw error("This request does not belong to the rider", 403);
  if (request.status !== "pending") return dispatchResult(request, false);
  const expiresAt = timestampMillis(request.offerExpiresAt);
  if (expiresAt === null || expiresAt > nowMillis) return dispatchResult(request, false);
  return advanceRideDispatch({
    rideId,
    actorUid: uid,
    actorRole: "rider",
    reason: "expired",
    requestId,
    db
  });
}

module.exports = {
  OFFER_TTL_SECONDS,
  normalizedCandidateIds,
  isEligibleCandidate,
  initializeRideDispatch,
  advanceRideDispatch,
  refreshRideDispatch,
  dispatchResult
};
