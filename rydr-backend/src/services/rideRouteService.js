const { admin, getFirestore } = require("../config/firebase");
const { getDirections } = require("./appleMapsService");

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function coordinateFrom(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = Number(value.latitude ?? value.lat ?? value._latitude);
  const longitude = Number(value.longitude ?? value.lng ?? value.lon ?? value._longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}

function rideCoordinate(ride, names) {
  for (const name of names) {
    const coordinate = coordinateFrom(ride[name]);
    if (coordinate) return coordinate;
  }
  return null;
}

function assertParticipant(ride, uid) {
  const participantIds = [
    ride.riderId,
    ride.driverId,
    ride.acceptedDriverId,
    ride.targetDriverId,
    ride.requestedDriverId
  ].filter(Boolean);
  if (!participantIds.includes(uid)) {
    throw error("Ride route is not available to this user.", 403);
  }
}

function routePoints(ride) {
  const pickup = rideCoordinate(ride, ["pickupCoordinate", "pickupLocation", "pickupGeoPoint"]);
  const stop = rideCoordinate(ride, ["stopCoordinate", "addedStopCoordinate", "stopLocation", "stopGeoPoint"]);
  const dropoff = rideCoordinate(ride, ["dropoffCoordinate", "destinationCoordinate", "dropoffLocation", "dropoffGeoPoint"]);
  if (!pickup || !dropoff) throw error("Ride pickup and drop-off coordinates are required.", 422);
  return [pickup, stop, dropoff].filter(Boolean);
}

async function calculateAndStoreRideRouteEstimate({ rideId, uid, departureDate }) {
  const db = getFirestore();
  const rideRef = db.collection("rides").doc(rideId);
  const requestRef = db.collection("rideRequests").doc(rideId);
  const outcomeRef = rideRef.collection("financial").doc("outcome");
  const [rideSnap, requestSnap, outcomeSnap] = await Promise.all([
    rideRef.get(),
    requestRef.get(),
    outcomeRef.get()
  ]);
  if (!rideSnap.exists && !requestSnap.exists) throw error("Ride not found.", 404);
  if (outcomeSnap.exists) throw error("A finalized ride route cannot be recalculated.", 409);

  const ride = {
    ...(requestSnap.exists ? requestSnap.data() : {}),
    ...(rideSnap.exists ? rideSnap.data() : {})
  };
  assertParticipant(ride, uid);
  if (
    ride.backendRouteProvider === "apple_maps" &&
    Number.isFinite(Number(ride.backendDistanceMeters)) &&
    Number.isFinite(Number(ride.backendDurationSeconds))
  ) {
    return {
      provider: "apple_maps",
      rideId,
      distanceMeters: Number(ride.backendDistanceMeters),
      distanceMiles: Number(ride.backendDistanceMiles),
      durationSeconds: Number(ride.backendDurationSeconds),
      durationMinutes: Number(ride.backendDurationMinutes),
      legs: Array.isArray(ride.backendRouteLegs) ? ride.backendRouteLegs : [],
      cached: true
    };
  }
  const points = routePoints(ride);
  const legs = [];
  for (let index = 0; index < points.length - 1; index += 1) {
    legs.push(await getDirections({
      origin: points[index],
      destination: points[index + 1],
      departureDate
    }));
  }

  const distanceMeters = legs.reduce((total, leg) => total + leg.route.distanceMeters, 0);
  const durationSeconds = legs.reduce((total, leg) => total + leg.route.durationSeconds, 0);
  const now = admin.firestore.Timestamp.now();
  const update = {
    backendRouteProvider: "apple_maps",
    backendRouteCalculatedAt: now,
    backendRouteCalculatedBy: "rydr-backend",
    backendDistanceMeters: distanceMeters,
    backendDistanceMiles: distanceMeters / 1609.344,
    backendDurationSeconds: durationSeconds,
    backendDurationMinutes: durationSeconds / 60,
    backendRouteLegs: legs.map((leg, index) => ({
      index,
      name: leg.route.name,
      distanceMeters: leg.route.distanceMeters,
      durationSeconds: leg.route.durationSeconds,
      hasTolls: leg.route.hasTolls,
      transportType: leg.route.transportType
    })),
    updatedAt: now
  };

  const batch = db.batch();
  if (rideSnap.exists) batch.set(rideRef, update, { merge: true });
  if (requestSnap.exists) batch.set(requestRef, update, { merge: true });
  await batch.commit();

  return {
    provider: "apple_maps",
    rideId,
    distanceMeters,
    distanceMiles: update.backendDistanceMiles,
    durationSeconds,
    durationMinutes: update.backendDurationMinutes,
    legs: legs.map((leg) => leg.route),
    cached: false
  };
}

module.exports = {
  calculateAndStoreRideRouteEstimate,
  coordinateFrom,
  routePoints
};
