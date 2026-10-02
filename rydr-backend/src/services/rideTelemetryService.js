const { admin, getFirestore } = require("../config/firebase");

const TELEMETRY_STATUSES = new Set([
  "enRouteToPickup", "navigatingToPickup", "arrivedAtPickup", "inProgress",
  "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"
]);

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function finite(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function normalizeTelemetry(payload) {
  const lat = finite(payload?.lat);
  const lng = finite(payload?.lng);
  if (lat === null || lng === null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw error("Valid telemetry coordinates are required", 400);
  }
  const speed = finite(payload?.speed);
  const course = finite(payload?.course);
  const horizontalAccuracy = finite(payload?.horizontalAccuracy);
  return {
    lat,
    lng,
    speed: speed !== null && speed >= 0 && speed <= 100 ? speed : null,
    course: course !== null && course >= 0 && course <= 360 ? course : null,
    horizontalAccuracy: horizontalAccuracy !== null && horizontalAccuracy >= 0 && horizontalAccuracy <= 500
      ? horizontalAccuracy
      : null
  };
}

async function recordRideTelemetry({ rideId, driverId, eventId, payload, db = getFirestore() }) {
  if (!eventId || !/^[A-Za-z0-9_-]{8,80}$/.test(eventId)) throw error("eventId is required", 400);
  const point = normalizeTelemetry(payload);
  const rideRef = db.collection("rides").doc(rideId);
  const eventRef = rideRef.collection("telemetry").doc(eventId);
  return db.runTransaction(async (tx) => {
    const [rideSnap, eventSnap] = await Promise.all([tx.get(rideRef), tx.get(eventRef)]);
    if (!rideSnap.exists) throw error("Ride not found", 404);
    if (eventSnap.exists) return { duplicate: true, recordedAt: null };
    const ride = rideSnap.data();
    if (ride.driverId !== driverId) throw error("Only the assigned driver may record telemetry", 403);
    if (!TELEMETRY_STATUSES.has(ride.status)) throw error("Ride is not accepting trip telemetry", 409);
    const now = admin.firestore.Timestamp.now();
    tx.create(eventRef, {
      rideId,
      driverId,
      riderId: ride.riderId,
      status: ride.status,
      ...point,
      recordedAt: now,
      receivedAt: now,
      source: "rydr_backend"
    });
    tx.set(rideRef, {
      driverLocation: { lat: point.lat, lng: point.lng, speed: point.speed, course: point.course, updatedAt: now },
      lastTelemetryAt: now,
      telemetryOwner: "backend",
      updatedAt: now
    }, { merge: true });
    return { duplicate: false, recordedAt: now.toDate().toISOString() };
  });
}

module.exports = { recordRideTelemetry, normalizeTelemetry, TELEMETRY_STATUSES };
