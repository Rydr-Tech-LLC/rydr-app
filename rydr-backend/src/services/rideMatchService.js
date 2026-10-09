const { admin, getFirestore } = require("../config/firebase");
const { getDirections } = require("./appleMapsService");
const { findBestDrivers } = require("./driverMatchingService");
const { isApprovedDriver, hasCurrentOnlinePresence } = require("./driverPresenceService");
const { configuredRateObject, quoteFingerprint } = require("./rideRequestService");
const { calculateOutcome, PRICING_VERSION } = require("./rideFinancialService");

const MATCH_SESSION_TTL_MS = 5 * 60 * 1000;
const SCHEDULED_RIDE_PROTECTION_WINDOW_MS = 3 * 60 * 60 * 1000;
const SCHEDULED_RIDE_ARRIVAL_BUFFER_SECONDS = 10 * 60;

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
    displayName: firstName(profile?.firstName || profile?.legalFirstName || profile?.displayName || profile?.name),
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

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (Number.isFinite(Number(value))) return Number(value);
  return null;
}

async function scheduledPickupCoordinate({ db, lock }) {
  const direct = lock.pickupCoordinate;
  if (direct && Number.isFinite(Number(direct.lat ?? direct.latitude)) && Number.isFinite(Number(direct.lng ?? direct.longitude))) {
    return coordinate(direct, "scheduledPickupCoordinate");
  }
  const requestId = String(lock.scheduledRideId || "").trim();
  if (!requestId) return null;
  const snapshot = await db.collection("scheduledRideRequests").doc(requestId).get();
  return snapshot.exists ? coordinate(snapshot.data().pickupCoordinate, "scheduledPickupCoordinate") : null;
}

async function driverCanFinishBeforeScheduledPickup({ candidate, db, pickup, dropoff, tripDurationSeconds, routeProvider, nowMillis }) {
  const locks = await db.collection("drivers").doc(candidate.id).collection("scheduledRideLocks")
    .where("status", "==", "active").limit(10).get();
  const upcoming = (locks.docs || [])
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .map((lock) => ({ lock, pickupMillis: timestampMillis(lock.scheduledPickupAt) }))
    .filter(({ pickupMillis }) => pickupMillis != null && pickupMillis > nowMillis)
    .sort((left, right) => left.pickupMillis - right.pickupMillis)[0];
  if (!upcoming || upcoming.pickupMillis - nowMillis > SCHEDULED_RIDE_PROTECTION_WINDOW_MS) return true;

  try {
    const protectedPickup = await scheduledPickupCoordinate({ db, lock: upcoming.lock });
    if (!protectedPickup) return false;
    const [toRider, toScheduledPickup] = await Promise.all([
      routeProvider({ origin: candidate.location, destination: pickup, departureDate: new Date(nowMillis).toISOString() }),
      routeProvider({
        origin: dropoff,
        destination: protectedPickup,
        departureDate: new Date(nowMillis + Number(tripDurationSeconds || 0) * 1000).toISOString()
      })
    ]);
    const requiredSeconds = Number(toRider.route?.durationSeconds || 0)
      + Number(tripDurationSeconds || 0)
      + Number(toScheduledPickup.route?.durationSeconds || 0)
      + SCHEDULED_RIDE_ARRIVAL_BUFFER_SECONDS;
    return requiredSeconds > 0 && nowMillis + requiredSeconds * 1000 <= upcoming.pickupMillis;
  } catch {
    // Protect the scheduled commitment when an authoritative travel-time check
    // cannot prove the additional ride is safe.
    return false;
  }
}

async function protectScheduledCommitments({ candidates, db, pickup, dropoff, tripDurationSeconds, routeProvider, nowMillis }) {
  const decisions = await Promise.all(candidates.map(async (candidate) => ({
    candidate,
    allowed: await driverCanFinishBeforeScheduledPickup({
      candidate, db, pickup, dropoff, tripDurationSeconds, routeProvider, nowMillis
    })
  })));
  return decisions.filter((decision) => decision.allowed).map((decision) => decision.candidate);
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
  const statusSnapshots = publicSnapshots.length > 0
    ? await db.getAll(...publicSnapshots.map((doc) => db.collection("driver_status").doc(doc.id)))
    : [];
  const canonicalById = new Map(canonicalSnapshots
    .filter((doc) => doc.exists && isApprovedDriver(doc.data()))
    .map((doc) => [doc.id, doc.data()]));
  const statusById = new Map(statusSnapshots
    .filter((doc) => doc.exists && hasCurrentOnlinePresence(doc.data(), now.toMillis()))
    .map((doc) => [doc.id, doc.data()]));
  const eligible = findBestDrivers({
    rideType,
    pickupCoordinate: pickup,
    dropoffCoordinate: dropoff,
    routeDistanceMiles: route.distanceMeters / 1609.344,
    candidates: publicSnapshots
      .filter((doc) => canonicalById.has(doc.id) && statusById.has(doc.id))
      .map((doc) => {
        const presence = doc.data();
        const status = statusById.get(doc.id);
        return {
          id: doc.id,
          profile: {
            ...presence,
            ...canonicalById.get(doc.id),
            isOnline: status.isOnline,
            availabilityStatus: status.availabilityStatus,
            approximateLocation: status.location || presence.approximateLocation,
            eligibleRideTypes: status.selectedRideTypes || presence.eligibleRideTypes
          }
        };
      }),
    requireOnline: true
  });
  if (eligible.length === 0) throw error("No nearby drivers are available", 409);

  const onTimeEligible = await protectScheduledCommitments({
    candidates: eligible,
    db,
    pickup,
    dropoff,
    tripDurationSeconds: route.durationSeconds,
    routeProvider,
    nowMillis: now.toMillis()
  });
  if (onTimeEligible.length === 0) throw error("No nearby drivers can complete this ride without risking a scheduled pickup", 409);

  const candidates = onTimeEligible.map((candidate) => {
    const rates = configuredRateObject(candidate.profile, rideType);
    if (!rates) return null;
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
  }).filter(Boolean);
  if (candidates.length === 0) throw error("No nearby drivers with a current rate card are available", 409);
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

module.exports = {
  createRideMatchSession,
  MATCH_SESSION_TTL_MS,
  SCHEDULED_RIDE_PROTECTION_WINDOW_MS,
  SCHEDULED_RIDE_ARRIVAL_BUFFER_SECONDS,
  publicDriverProjection,
  driverCanFinishBeforeScheduledPickup
};
