const { admin, getFirestore } = require("../config/firebase");
const { getDirections } = require("./appleMapsService");
const { findBestDrivers } = require("./driverMatchingService");
const { isApprovedDriver } = require("./driverPresenceService");
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

function firstName(value) {
  const name = String(value || "").trim();
  return name ? name.split(/\s+/)[0] : "Rydr Driver";
}

function publicDriverProjection(profile, location) {
  const vehicle = profile?.vehicle && typeof profile.vehicle === "object" ? profile.vehicle : {};
  const vehicleSummary = String(profile?.vehicleSummary || profile?.carMakeModel || [
    vehicle.color,
    vehicle.year,
    vehicle.make,
    vehicle.model
  ].filter(Boolean).join(" ") || "Verified Rydr vehicle").trim();
  const rawGender = String(profile?.gender || profile?.driverGender || profile?.genderIdentity || "").toLowerCase();
  return {
    displayName: firstName(profile?.displayName || profile?.firstName || profile?.name),
    profilePhotoURL: profile?.profilePhotoURL || profile?.profileImage || null,
    vehicleImageURL: profile?.vehicleImageURL || profile?.carImage || vehicle.imageURL || null,
    vehicleSummary,
    rating: Number.isFinite(Number(profile?.rating ?? profile?.driverRating))
      ? Number(profile.rating ?? profile.driverRating)
      : 5,
    ratingCount: Math.max(0, Number(profile?.ratingCount) || 0),
    completedRideCount: Math.max(0, Number(profile?.completedRideCount ?? profile?.lifetimeRideCount) || 0),
    acceptanceRate: Number.isFinite(Number(profile?.acceptanceRate)) ? Number(profile.acceptanceRate) : null,
    compliments: Array.isArray(profile?.compliments) ? profile.compliments.map(String).slice(0, 12) : [],
    gender: rawGender === "male" ? "Male" : rawGender === "female" ? "Female" : null,
    approximateLocation: { lat: location.latitude, lng: location.longitude }
  };
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
  const publicSnapshots = snapshot.docs ?? [];
  const canonicalSnapshots = publicSnapshots.length > 0
    ? await db.getAll(...publicSnapshots.map((doc) => db.collection("drivers").doc(doc.id)))
    : [];
  const canonicalById = new Map(canonicalSnapshots
    .filter((doc) => doc.exists && isApprovedDriver(doc.data()))
    .map((doc) => [doc.id, doc.data()]));
  const eligible = findBestDrivers({
    rideType,
    pickupCoordinate: pickup,
    dropoffCoordinate: dropoff,
    routeDistanceMiles: route.distanceMeters / 1609.344,
    candidates: publicSnapshots
      .filter((doc) => canonicalById.has(doc.id))
      .map((doc) => {
        const presence = doc.data();
        return {
          id: doc.id,
          profile: {
            ...presence,
            ...canonicalById.get(doc.id),
            isOnline: presence.isOnline,
            availabilityStatus: presence.availabilityStatus,
            approximateLocation: presence.approximateLocation,
            eligibleRideTypes: presence.eligibleRideTypes
          }
        };
      }),
    requireOnline: true
  });
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
      matchScore: candidate.matchScore,
      matchReasons: candidate.matchReasons,
      preferenceMatch: candidate.preferenceMatch,
      distanceToPickupMiles: Math.round(candidate.distanceToPickupMiles * 10) / 10,
      driver: publicDriverProjection(candidate.profile, candidate.location),
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

module.exports = { createRideMatchSession, MATCH_SESSION_TTL_MS, publicDriverProjection };
