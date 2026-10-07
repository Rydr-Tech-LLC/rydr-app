const crypto = require("node:crypto");
const { admin, getFirestore } = require("../config/firebase");
const { getDirections } = require("./appleMapsService");
const {
  calculateOutcome,
  tierFor,
  TIERS,
  DEFAULT_MINIMUM_FARE_CENTS,
  PRICING_VERSION
} = require("./rideFinancialService");
const {
  OFFER_TTL_SECONDS,
  normalizedCandidateIds,
  isEligibleCandidate
} = require("./rideDispatchService");
const { isApprovedDriver } = require("./driverPresenceService");

function error(message, statusCode, details) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (details) err.details = details;
  return err;
}

function text(value, maximumLength = 240) {
  const normalized = typeof value === "string" ? value.trim() : "";
  return normalized.length > 0 && normalized.length <= maximumLength ? normalized : null;
}

function coordinate(value, fieldName) {
  if (!value || typeof value !== "object") throw error(`${fieldName} is required`, 422);
  const latitude = Number(value.latitude ?? value.lat);
  const longitude = Number(value.longitude ?? value.lng ?? value.lon);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)
      || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw error(`${fieldName} is invalid`, 422);
  }
  return { latitude, longitude };
}

function canonicalRateKey(rideType) {
  return tierFor(rideType);
}

function nonnegativeNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function tierEntry(values, tier, requestedRideType) {
  if (!values || typeof values !== "object") return {};
  return values[tier]
    ?? values[String(requestedRideType || "")]
    ?? values[String(requestedRideType || "").trim()]
    ?? Object.entries(values).find(([key]) => tierFor(key) === tier)?.[1]
    ?? {};
}

function rateObject(profile, rideType) {
  const tier = canonicalRateKey(rideType);
  const config = TIERS[tier];
  const rawRates = profile?.tierRates && typeof profile.tierRates === "object" ? profile.tierRates : {};
  const raw = tierEntry(rawRates, tier, rideType);
  const usesSuggestedPricing = raw.useSuggestedPricing === true;
  const suggested = tierEntry(profile?.resolvedSuggestedRates, tier, rideType);
  const centsOrNull = (value) => {
    const number = nonnegativeNumber(value);
    return number == null ? null : Math.round(number);
  };
  const dollarsToCents = (value) => {
    const number = nonnegativeNumber(value);
    return number == null ? null : Math.round(number * 100);
  };

  const minimumFareCents = usesSuggestedPricing
    ? centsOrNull(suggested.minimumFareCents) ?? DEFAULT_MINIMUM_FARE_CENTS
    : dollarsToCents(raw.minimumFare) ?? DEFAULT_MINIMUM_FARE_CENTS;
  const perMileCents = usesSuggestedPricing
    ? centsOrNull(suggested.perMileCents) ?? config.suggestedMile
    : dollarsToCents(raw.perMile) ?? dollarsToCents(profile?.perMile) ?? config.suggestedMile;
  const perMinuteCents = usesSuggestedPricing
    ? centsOrNull(suggested.perMinuteCents) ?? config.suggestedMinute
    : dollarsToCents(raw.perMinute) ?? dollarsToCents(profile?.perMinute) ?? config.suggestedMinute;

  return { tier, minimumFareCents, perMileCents, perMinuteCents, usesSuggestedPricing };
}

function quoteFingerprint({ riderId, driverId, rideType, pickup, dropoff, route, rates }) {
  const canonical = JSON.stringify({
    riderId,
    driverId,
    rideType: canonicalRateKey(rideType),
    pickup: [pickup.latitude.toFixed(6), pickup.longitude.toFixed(6)],
    dropoff: [dropoff.latitude.toFixed(6), dropoff.longitude.toFixed(6)],
    distanceMeters: Math.round(route.distanceMeters),
    durationSeconds: Math.round(route.durationSeconds),
    minimumFareCents: rates.minimumFareCents,
    perMileCents: rates.perMileCents,
    perMinuteCents: rates.perMinuteCents,
    pricingVersion: PRICING_VERSION
  });
  return crypto.createHash("sha256").update(canonical).digest("hex");
}

function deterministicRideId(riderId, idempotencyKey) {
  return `ride_${crypto.createHash("sha256").update(`${riderId}:${idempotencyKey}`).digest("hex").slice(0, 32)}`;
}

function validIdempotencyKey(value) {
  const normalized = text(value, 128);
  if (!normalized || !/^[A-Za-z0-9_-]{8,128}$/.test(normalized)) {
    throw error("idempotencyKey is required", 400);
  }
  return normalized;
}

async function verifyPaymentReadiness({ authorization, fetchImpl = globalThis.fetch }) {
  const base = String(process.env.RYDR_STRIPE_BACKEND_URL || "https://rydr-stripe-backend.onrender.com").replace(/\/$/, "");
  if (!authorization) throw error("Payment authentication is required", 401);
  let response;
  try {
    response = await fetchImpl(`${base}/list-payment-methods`, {
      method: "POST",
      headers: { Authorization: authorization, "Content-Type": "application/json" },
      body: "{}"
    });
  } catch {
    throw error("Payment readiness could not be verified", 503);
  }
  if (!response.ok) throw error("Payment readiness could not be verified", response.status === 401 ? 401 : 503);
  const payload = await response.json();
  if (!Array.isArray(payload.paymentMethods) || payload.paymentMethods.length === 0) {
    throw error("Add a payment method before requesting a ride", 409);
  }
  return true;
}

async function createRideRequest({
  riderId,
  authorization,
  payload,
  db = getFirestore(),
  routeProvider = getDirections,
  paymentVerifier = verifyPaymentReadiness,
  authUserProvider = (uid) => admin.auth().getUser(uid),
  authoritativeRateOverride = null,
  authoritativeRouteOverride = null,
  trustedScheduledActivation = false,
  now = admin.firestore.Timestamp.now()
}) {
  const idempotencyKey = validIdempotencyKey(payload?.idempotencyKey);
  const rideId = deterministicRideId(riderId, idempotencyKey);
  const requestRef = db.collection("rideRequests").doc(rideId);
  const signalRef = db.collection("rideRequestSignals").doc(rideId);
  const idempotencyRef = db.collection("rideRequestIdempotency").doc(`${riderId}_${idempotencyKey}`);

  const existingIdempotency = await idempotencyRef.get();
  if (existingIdempotency.exists) {
    const existing = existingIdempotency.data();
    return { rideId: existing.rideId, duplicate: true, quoteFingerprint: existing.quoteFingerprint ?? null };
  }

  const selectedCandidateId = text(payload?.selectedCandidateId, 128);
  const pickupName = text(payload?.pickup);
  const dropoffName = text(payload?.dropoff);
  const rideType = text(payload?.rideType, 80);
  if (!selectedCandidateId || !pickupName || !dropoffName || !rideType) {
    throw error("pickup, dropoff, rideType, and selectedCandidateId are required", 422);
  }
  const pickup = coordinate(payload?.pickupCoordinate, "pickupCoordinate");
  const dropoff = coordinate(payload?.dropoffCoordinate, "dropoffCoordinate");

  let matchSessionRef = null;
  let matchSession = null;
  let sessionCandidate = null;
  if (!trustedScheduledActivation) {
    const matchSessionId = text(payload?.matchSessionId, 128);
    const suppliedFingerprint = text(payload?.quoteFingerprint, 128);
    if (!matchSessionId || !suppliedFingerprint) throw error("matchSessionId and quoteFingerprint are required", 409);
    matchSessionRef = db.collection("rideMatchSessions").doc(matchSessionId);
    const sessionSnap = await matchSessionRef.get();
    if (!sessionSnap.exists) throw error("The driver match session no longer exists", 409);
    matchSession = sessionSnap.data();
    if (matchSession.riderId !== riderId || matchSession.status !== "open") throw error("The driver match session is no longer valid", 409);
    const sessionExpiry = typeof matchSession.expiresAt?.toMillis === "function" ? matchSession.expiresAt.toMillis() : 0;
    if (sessionExpiry <= now.toMillis()) throw error("The driver match session expired. Refresh nearby drivers.", 409);
    if (tierFor(matchSession.rideType) !== tierFor(rideType)) throw error("The ride type changed after matching", 409);
    const sameCoordinate = (left, right) => Math.abs(Number(left?.lat) - right.latitude) < 0.000001
      && Math.abs(Number(left?.lng) - right.longitude) < 0.000001;
    if (!sameCoordinate(matchSession.pickupCoordinate, pickup) || !sameCoordinate(matchSession.dropoffCoordinate, dropoff)) {
      throw error("The route changed after matching. Refresh nearby drivers.", 409);
    }
    sessionCandidate = Array.isArray(matchSession.candidates)
      ? matchSession.candidates.find((candidate) => candidate.driverId === selectedCandidateId)
      : null;
    if (!sessionCandidate || sessionCandidate.quoteFingerprint !== suppliedFingerprint) {
      throw error("The selected driver quote is not part of this match session", 409);
    }
  }

  const riderRef = db.collection("riders").doc(riderId);
  const publicDriverRef = db.collection("publicDriverProfiles").doc(selectedCandidateId);
  const canonicalDriverRef = db.collection("drivers").doc(selectedCandidateId);
  const [riderSnap, publicDriverSnap, canonicalDriverSnap] = await Promise.all([
    riderRef.get(),
    publicDriverRef.get(),
    canonicalDriverRef.get()
  ]);
  if (!riderSnap.exists) throw error("Rider profile not found", 403);
  const rider = riderSnap.data();
  if (["deletion_requested", "removed", "suspended"].includes(String(rider.accountStatus || ""))) {
    throw error("This rider account cannot request rides", 403);
  }
  if (!publicDriverSnap.exists || !isEligibleCandidate(publicDriverSnap.data(), rideType)
      || !canonicalDriverSnap.exists || !isApprovedDriver(canonicalDriverSnap.data())) {
    throw error("The selected driver is no longer available", 409);
  }

  await paymentVerifier({ riderId, authorization });

  const sessionRoute = matchSession?.backendRoute ?? null;
  const routeResult = authoritativeRouteOverride
    ? { route: authoritativeRouteOverride }
    : sessionRoute
      ? { route: sessionRoute }
    : await routeProvider({ origin: pickup, destination: dropoff, departureDate: new Date().toISOString() });
  const route = routeResult.route;
  if (!route || !Number.isFinite(Number(route.distanceMeters)) || !Number.isFinite(Number(route.durationSeconds))) {
    throw error("A backend route could not be calculated", 422);
  }

  const rates = authoritativeRateOverride ?? rateObject(canonicalDriverSnap.data(), rideType);
  const distanceMiles = Number(route.distanceMeters) / 1609.344;
  const durationMinutes = Number(route.durationSeconds) / 60;
  const estimate = calculateOutcome({
    rideType,
    backendDistanceMiles: distanceMiles,
    backendDurationMinutes: durationMinutes,
    driverMinimumFareCents: rates.minimumFareCents,
    driverRatePerMileCents: rates.perMileCents,
    driverRatePerMinuteCents: rates.perMinuteCents
  });
  const fingerprint = quoteFingerprint({ riderId, driverId: selectedCandidateId, rideType, pickup, dropoff, route, rates });
  if (!trustedScheduledActivation && fingerprint !== sessionCandidate.quoteFingerprint) {
    throw error("The selected driver's pricing changed. Refresh nearby drivers.", 409);
  }
  const candidateIds = trustedScheduledActivation
    ? normalizedCandidateIds([selectedCandidateId])
    : normalizedCandidateIds(matchSession.candidateIds);
  const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + OFFER_TTL_SECONDS * 1000);
  const authUser = await authUserProvider(riderId);
  const riderName = text(authUser.displayName, 120) || text(rider.displayName, 120) || text(rider.firstName, 120) || "Rydr rider";

  const request = {
    id: rideId,
    riderId,
    riderName,
    riderPhotoURL: authUser.photoURL || rider.profilePhotoURL || "",
    riderVerified: rider.verifiedRider === true || rider.identityVerified === true,
    verifiedRider: rider.verifiedRider === true || rider.identityVerified === true,
    driverId: selectedCandidateId,
    pickup: pickupName,
    dropoff: dropoffName,
    pickupCoordinate: { lat: pickup.latitude, lng: pickup.longitude },
    pickupGeoPoint: new admin.firestore.GeoPoint(pickup.latitude, pickup.longitude),
    dropoffCoordinate: { lat: dropoff.latitude, lng: dropoff.longitude },
    dropoffGeoPoint: new admin.firestore.GeoPoint(dropoff.latitude, dropoff.longitude),
    rideType,
    ridePreferences: payload.ridePreferences && typeof payload.ridePreferences === "object" ? payload.ridePreferences : {},
    replacementForRideId: text(payload.replacementForRideId, 128),
    scheduledRideId: text(payload.scheduledRideId, 128),
    rydrBankCode: text(payload.rydrBankCode, 80),
    source: payload.source === "scheduledRydr" ? "scheduledRydr" : "standardRydr",
    status: "pending",
    dispatchStatus: "offered",
    dispatchAttemptNumber: 1,
    dispatchCandidateIds: candidateIds,
    attemptedDriverIds: [],
    offerCreatedAt: now,
    offerExpiresAt: expiresAt,
    dispatchUpdatedAt: now,
    lifecycleOwner: "backend",
    pricingVersion: PRICING_VERSION,
    quoteFingerprint: fingerprint,
    driverMinimumFareCents: rates.minimumFareCents,
    driverRatePerMileCents: rates.perMileCents,
    driverRatePerMinuteCents: rates.perMinuteCents,
    driverUsesSuggestedPricing: rates.usesSuggestedPricing,
    backendRouteProvider: "apple_maps",
    backendRouteCalculatedAt: now,
    backendRouteCalculatedBy: "rydr-backend",
    backendDistanceMeters: Number(route.distanceMeters),
    backendDistanceMiles: distanceMiles,
    backendDurationSeconds: Number(route.durationSeconds),
    backendDurationMinutes: durationMinutes,
    backendRouteLegs: [{
      index: 0,
      name: route.name ?? null,
      distanceMeters: Number(route.distanceMeters),
      durationSeconds: Number(route.durationSeconds),
      hasTolls: route.hasTolls ?? null,
      transportType: route.transportType || "AUTOMOBILE"
    }],
    estimatedRiderTotalCents: estimate.finalRiderChargeCents,
    estimatedDriverPayoutCents: estimate.driverPayoutCents,
    estimatedPlatformShareCents: estimate.platformShareCents,
    createdAt: now,
    updatedAt: now
  };
  Object.keys(request).forEach((key) => request[key] == null && delete request[key]);

  const transactionResult = await db.runTransaction(async (tx) => {
    const [duplicate, currentMatchSession] = await Promise.all([
      tx.get(idempotencyRef),
      matchSessionRef ? tx.get(matchSessionRef) : Promise.resolve(null)
    ]);
    if (duplicate.exists) {
      const existing = duplicate.data();
      return {
        duplicate: true,
        rideId: existing.rideId,
        quoteFingerprint: existing.quoteFingerprint ?? null
      };
    }
    if (matchSessionRef && (!currentMatchSession?.exists || currentMatchSession.data().status !== "open")) {
      throw error("The driver match session is no longer valid", 409);
    }
    tx.create(requestRef, request);
    tx.create(signalRef, {
      id: rideId,
      riderId,
      driverId: selectedCandidateId,
      rideType,
      status: "pending",
      source: request.source,
      pickupCoordinate: request.pickupCoordinate,
      pickupGeoPoint: request.pickupGeoPoint,
      dispatchAttemptNumber: 1,
      expiresAt,
      createdAt: now,
      updatedAt: now
    });
    tx.create(idempotencyRef, { riderId, rideId, quoteFingerprint: fingerprint, createdAt: now });
    if (matchSessionRef) tx.set(matchSessionRef, { status: "consumed", consumedAt: now, rideId }, { merge: true });
    return { duplicate: false, rideId, quoteFingerprint: fingerprint };
  });

  if (transactionResult.duplicate) return transactionResult;

  return {
    rideId,
    duplicate: false,
    quoteFingerprint: fingerprint,
    route: { distanceMiles, durationMinutes },
    estimate: {
      riderTotalCents: estimate.finalRiderChargeCents,
      driverPayoutCents: estimate.driverPayoutCents,
      platformShareCents: estimate.platformShareCents
    }
  };
}

module.exports = {
  createRideRequest,
  verifyPaymentReadiness,
  deterministicRideId,
  quoteFingerprint,
  rateObject,
  tierEntry
};
