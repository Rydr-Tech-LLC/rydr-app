const { admin, getFirestore } = require("../config/firebase");
const { getDirections } = require("./appleMapsService");
const { isEligibleCandidate } = require("./rideDispatchService");
const { rateObject, quoteFingerprint } = require("./rideRequestService");
const { calculateOutcome, PRICING_VERSION } = require("./rideFinancialService");

const MATCH_SESSION_TTL_MS = 5 * 60 * 1000;

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function coordinate(value, name) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) throw error(`${name} is required`, 422);
  return { latitude, longitude };
}

function profileCoordinate(profile) {
  for (const value of [profile?.approximateLocation, profile?.location, profile]) {
    const latitude = Number(value?.latitude ?? value?.lat);
    const longitude = Number(value?.longitude ?? value?.lng);
    if (Number.isFinite(latitude) && Number.isFinite(longitude)) return { latitude, longitude };
  }
  const point = profile?.geoPoint;
  return Number.isFinite(point?.latitude) && Number.isFinite(point?.longitude)
    ? { latitude: point.latitude, longitude: point.longitude }
    : null;
}

function distanceMiles(a, b) {
  const radius = 3958.7613;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLng = radians(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return radius * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

async function createRideMatchSession({ riderId, payload, db = getFirestore(), routeProvider = getDirections, now = admin.firestore.Timestamp.now() }) {
  const pickup = coordinate(payload?.pickupCoordinate, "pickupCoordinate");
  const dropoff = coordinate(payload?.dropoffCoordinate, "dropoffCoordinate");
  const rideType = typeof payload?.rideType === "string" ? payload.rideType.trim() : "";
  if (!rideType) throw error("rideType is required", 422);
  const routeResult = await routeProvider({ origin: pickup, destination: dropoff, departureDate: new Date().toISOString() });
  const route = routeResult.route;
  if (!route || route.distanceMeters <= 0 || route.durationSeconds <= 0) throw error("A route could not be calculated", 422);

  const snapshot = await db.collection("publicDriverProfiles").where("isOnline", "==", true).limit(200).get();
  const eligible = (snapshot.docs ?? [])
    .filter((doc) => isEligibleCandidate(doc.data(), rideType))
    .map((doc) => ({ id: doc.id, profile: doc.data(), location: profileCoordinate(doc.data()) }))
    .filter((candidate) => candidate.location && distanceMiles(pickup, candidate.location) <= 30)
    .sort((a, b) => distanceMiles(pickup, a.location) - distanceMiles(pickup, b.location)
      || Number(b.profile.rating || 0) - Number(a.profile.rating || 0))
    .slice(0, 20);
  if (eligible.length === 0) throw error("No nearby drivers are available", 409);

  const candidates = eligible.map((candidate) => {
    const rates = rateObject(candidate.profile, rideType);
    const outcome = calculateOutcome({
      rideType,
      backendDistanceMiles: route.distanceMeters / 1609.344,
      backendDurationMinutes: route.durationSeconds / 60,
      driverMinimumFareCents: rates.minimumFareCents,
      driverRatePerMileCents: rates.perMileCents,
      driverRatePerMinuteCents: rates.perMinuteCents
    });
    return {
      driverId: candidate.id,
      quoteFingerprint: quoteFingerprint({ riderId, driverId: candidate.id, rideType, pickup, dropoff, route, rates }),
      rates,
      estimatedRiderTotalCents: outcome.finalRiderChargeCents,
      estimatedDriverPayoutCents: outcome.driverPayoutCents
    };
  });
  const sessionRef = db.collection("rideMatchSessions").doc();
  const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + MATCH_SESSION_TTL_MS);
  await sessionRef.create({
    riderId,
    rideType,
    pickupCoordinate: { lat: pickup.latitude, lng: pickup.longitude },
    dropoffCoordinate: { lat: dropoff.latitude, lng: dropoff.longitude },
    backendRoute: {
      name: route.name ?? null,
      distanceMeters: Number(route.distanceMeters),
      durationSeconds: Number(route.durationSeconds),
      hasTolls: route.hasTolls ?? null,
      transportType: route.transportType || "AUTOMOBILE"
    },
    candidateIds: candidates.map((candidate) => candidate.driverId),
    candidates,
    riderPreferences: payload.riderPreferences && typeof payload.riderPreferences === "object" ? payload.riderPreferences : {},
    pricingVersion: PRICING_VERSION,
    status: "open",
    createdAt: now,
    expiresAt
  });
  return {
    matchSessionId: sessionRef.id,
    expiresAtMillis: expiresAt.toMillis(),
    route: { distanceMiles: route.distanceMeters / 1609.344, durationMinutes: route.durationSeconds / 60 },
    candidates
  };
}

module.exports = { createRideMatchSession, MATCH_SESSION_TTL_MS };
