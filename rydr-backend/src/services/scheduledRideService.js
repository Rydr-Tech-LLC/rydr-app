const { admin, getFirestore } = require("../config/firebase");
const { getDirections } = require("./appleMapsService");
const { calculateOutcome, tierFor, PRICING_VERSION } = require("./rideFinancialService");
const { configuredRateObject, verifyPaymentReadiness, createRideRequest } = require("./rideRequestService");
const { findBestDrivers } = require("./driverMatchingService");
const { hasCurrentOnlinePresence } = require("./driverPresenceService");

const MINIMUM_LEAD_TIME_MS = 60 * 1000;
const MAXIMUM_LEAD_TIME_MS = 30 * 24 * 60 * 60 * 1000;
const CHECK_IN_LEAD_MS = 60 * 60 * 1000;
const CHECK_IN_CUTOFF_MS = 15 * 60 * 1000;
const ACTIVATION_BUFFER_SECONDS = 6 * 60;
const DRIVER_RESPONSE_LIMIT = 3;
const OPPORTUNITY_LIMIT = 20;
const REPLACEMENT_CUTOFF_MS = 15 * 60 * 1000;
const ONLINE_READINESS_WINDOW_MS = 60 * 60 * 1000;
const MINIMUM_ONLINE_LEAD_MS = 20 * 60 * 1000;
const ONLINE_ARRIVAL_BUFFER_SECONDS = 10 * 60;
const DISPATCH_FALLBACK_WINDOW_MS = 15 * 60 * 1000;
const DISPATCH_FALLBACK_LEAD_MS = 5 * 60 * 1000;

function error(message, statusCode, details) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (details) err.details = details;
  return err;
}

function text(value, max = 240) {
  const result = typeof value === "string" ? value.trim() : "";
  return result && result.length <= max ? result : null;
}

function validIdempotencyKey(value) {
  const normalized = text(value, 128);
  if (!normalized || !/^[A-Za-z0-9_-]{8,128}$/.test(normalized)) {
    throw error("idempotencyKey is required", 400);
  }
  return normalized;
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (Number.isFinite(Number(value))) return Number(value);
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function isPastDueUndispatchedScheduledRide(request, nowMillis = Date.now()) {
  const pickupMillis = timestampMillis(request?.scheduledPickupAt);
  return request?.status === "expired"
    || (!request?.activeRideId && pickupMillis != null && pickupMillis < nowMillis);
}

function coordinate(value, name) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)
      || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw error(`${name} is invalid`, 422);
  }
  return { latitude, longitude };
}

function scheduledCandidateEligible(profile, rideType) {
  if (!profile || profile.standardDispatchEnabled === false) return false;
  const approvalStatus = String(profile.driverApprovalStatus ?? profile.approvalStatus ?? "pending").toLowerCase();
  if (profile.isApproved !== true && approvalStatus !== "approved") return false;
  if (["suspended", "removed", "deletion_requested"].includes(String(profile.accountStatus || "").toLowerCase())
      || String(profile.safetyReviewStatus || "").toLowerCase() === "suspended"
      || profile.safetyHold === true) return false;
  const supported = profile.eligibleRideTypes ?? profile.selectedRideTypes ?? profile.rideTypes ?? profile.supportedRideTypes ?? [];
  return !Array.isArray(supported) || supported.length === 0 || supported.some((value) => tierFor(value) === tierFor(rideType));
}

function quoteFor({ rideType, route, rates }) {
  const outcome = calculateOutcome({
    rideType,
    backendDistanceMiles: route.distanceMeters / 1609.344,
    backendDurationMinutes: route.durationSeconds / 60,
    driverMinimumFareCents: rates.minimumFareCents,
    driverRatePerMileCents: rates.perMileCents,
    driverRatePerMinuteCents: rates.perMinuteCents
  });
  return {
    totalCents: outcome.finalRiderChargeCents,
    baseFareCents: outcome.rideSubtotalCents,
    bookingFeeCents: outcome.bookingFeeCents,
    driverPayoutCents: outcome.driverPayoutCents,
    platformShareCents: outcome.platformShareCents
  };
}

function validateSchedule(value, nowMillis = Date.now()) {
  const pickupMillis = timestampMillis(value);
  if (pickupMillis == null) throw error("scheduledPickupAt is required", 422);
  if (pickupMillis < nowMillis + MINIMUM_LEAD_TIME_MS) throw error("Choose a scheduled pickup time at least one minute from now", 422);
  if (pickupMillis > nowMillis + MAXIMUM_LEAD_TIME_MS) throw error("Scheduled rides may be booked up to 30 days ahead", 422);
  return pickupMillis;
}

function requestPublicFields(data) {
  return {
    id: data.id,
    status: data.status,
    mode: data.mode,
    scheduledPickupAtMillis: timestampMillis(data.scheduledPickupAt),
    quote: data.quote,
    riderApprovedMaxCents: data.riderApprovedMaxCents,
    assignedDriverId: data.assignedDriverId ?? null,
    lockedPriceCents: data.lockedPriceCents ?? null,
    activationAtMillis: timestampMillis(data.activationAt),
    activeRideId: data.activeRideId ?? null
  };
}

async function candidateSnapshots(db) {
  const snapshot = await db.collection("publicDriverProfiles").limit(200).get();
  return snapshot.docs ?? [];
}

async function eligibleCandidates({
  db,
  rideType,
  pickup,
  dropoff,
  routeDistanceMiles,
  scheduledRideId,
  scheduledPickupMillis,
  durationMinutes,
  excludedDriverIds = [],
  requireOnline = false,
  nowMillis = Date.now()
}) {
  const excluded = new Set(excludedDriverIds);
  const candidates = [];
  const publicSnapshots = await candidateSnapshots(db);
  const canonicalSnapshots = publicSnapshots.length > 0
    ? await db.getAll(...publicSnapshots.map((snapshot) => db.collection("drivers").doc(snapshot.id)))
    : [];
  const statusSnapshots = requireOnline && publicSnapshots.length > 0
    ? await db.getAll(...publicSnapshots.map((snapshot) => db.collection("driver_status").doc(snapshot.id)))
    : [];
  const canonicalById = new Map(canonicalSnapshots.filter((snapshot) => snapshot.exists).map((snapshot) => [snapshot.id, snapshot.data()]));
  const statusById = new Map(statusSnapshots
    .filter((snapshot) => snapshot.exists && hasCurrentOnlinePresence(snapshot.data(), nowMillis))
    .map((snapshot) => [snapshot.id, snapshot.data()]));
  for (const snapshot of publicSnapshots) {
    if (excluded.has(snapshot.id)) continue;
    const canonical = canonicalById.get(snapshot.id);
    if (!scheduledCandidateEligible(canonical, rideType)) continue;
    if (requireOnline && !statusById.has(snapshot.id)) continue;
    const presence = snapshot.data();
    const liveStatus = statusById.get(snapshot.id);
    const profile = {
      ...presence,
      ...canonical,
      isOnline: liveStatus?.isOnline ?? presence.isOnline,
      availabilityStatus: liveStatus?.availabilityStatus ?? presence.availabilityStatus,
      approximateLocation: liveStatus?.location ?? presence.approximateLocation,
      eligibleRideTypes: liveStatus?.selectedRideTypes ?? presence.eligibleRideTypes ?? canonical.eligibleRideTypes
    };
    const locks = await db.collection("drivers").doc(snapshot.id).collection("scheduledRideLocks")
      .where("status", "==", "active").limit(25).get();
    const requestedStart = scheduledPickupMillis - 30 * 60 * 1000;
    const requestedEnd = scheduledPickupMillis + (durationMinutes + 60) * 60 * 1000;
    const conflicts = (locks.docs ?? []).some((lock) => {
      if (lock.id === scheduledRideId) return false;
      const data = lock.data();
      const start = timestampMillis(data.scheduledPickupAt);
      if (start == null) return true;
      const end = start + (Number(data.estimatedDurationMinutes || 0) + 60) * 60 * 1000;
      return requestedStart < end && requestedEnd > start - 30 * 60 * 1000;
    });
    if (conflicts) continue;
    candidates.push({ id: snapshot.id, profile });
  }
  return findBestDrivers({
    rideType,
    pickupCoordinate: pickup,
    dropoffCoordinate: dropoff,
    routeDistanceMiles,
    candidates,
    requireOnline,
    maxResults: OPPORTUNITY_LIMIT
  });
}

async function verifyRiderCanSchedule(db, riderId) {
  const snapshot = await db.collection("riders").doc(riderId).get();
  if (!snapshot.exists) throw error("Rider profile not found", 403);
  const status = String(snapshot.data().accountStatus || "").toLowerCase();
  if (["deletion_requested", "removed", "suspended"].includes(status)) {
    throw error("This rider account cannot schedule rides", 403);
  }
}

async function routeForPayload(payload, routeProvider) {
  const pickup = coordinate(payload.pickupCoordinate, "pickupCoordinate");
  const dropoff = coordinate(payload.dropoffCoordinate, "dropoffCoordinate");
  const result = await routeProvider({
    origin: pickup,
    destination: dropoff,
    departureDate: new Date(timestampMillis(payload.scheduledPickupAt) || Date.now()).toISOString()
  });
  if (!result.route || result.route.distanceMeters <= 0 || result.route.durationSeconds <= 0) {
    throw error("The scheduled route could not be calculated", 422);
  }
  return { pickup, dropoff, route: result.route };
}

async function buildCandidateQuotes({
  db,
  rideType,
  pickup,
  dropoff,
  route,
  scheduledRideId,
  scheduledPickupMillis,
  excludedDriverIds,
  requireOnline = false,
  arriveByMillis = null,
  rateOverride = null,
  quoteOverride = null,
  routeProvider = getDirections,
  nowMillis = Date.now()
}) {
  let candidates = await eligibleCandidates({
    db,
    rideType,
    pickup,
    dropoff,
    routeDistanceMiles: route.distanceMeters / 1609.344,
    scheduledRideId,
    scheduledPickupMillis,
    durationMinutes: route.durationSeconds / 60,
    excludedDriverIds,
    requireOnline,
    nowMillis
  });
  if (requireOnline && Number.isFinite(arriveByMillis)) {
    const arrivalChecks = await Promise.all(candidates.map(async (candidate) => {
      try {
        const result = await routeProvider({
          origin: candidate.location,
          destination: pickup,
          departureDate: new Date(nowMillis).toISOString()
        });
        const etaSeconds = Number(result.route?.durationSeconds || 0);
        return etaSeconds > 0 && nowMillis + (etaSeconds + 5 * 60) * 1000 <= arriveByMillis;
      } catch {
        return false;
      }
    }));
    candidates = candidates.filter((_, index) => arrivalChecks[index]);
  }
  return candidates.map((candidate) => {
    const rates = rateOverride || configuredRateObject(candidate.profile, rideType);
    if (!rates) return null;
    return {
      driverId: candidate.id,
      rideType,
      driverName: text(candidate.profile.firstName, 120) || text(candidate.profile.legalFirstName, 120) || text(candidate.profile.displayName, 120) || "Rydr Driver",
      driverPhotoURL: text(candidate.profile.profilePhotoURL, 1000),
      vehicleSummary: text(candidate.profile.vehicleSummary, 240) || text(candidate.profile.carMakeModel, 240),
      rating: Number(candidate.profile.rating || 0),
      ratingCount: Number(candidate.profile.ratingCount || 0),
      distanceToPickupMiles: Math.round(candidate.distanceToPickupMiles * 10) / 10,
      matchScore: candidate.matchScore,
      matchReasons: candidate.matchReasons,
      preferenceMatch: candidate.preferenceMatch,
      rates,
      quote: quoteOverride || quoteFor({ rideType, route, rates })
    };
  }).filter(Boolean);
}

async function previewScheduledRide({ riderId, authorization, payload, db = getFirestore(), routeProvider = getDirections, paymentVerifier = verifyPaymentReadiness, nowMillis = Date.now() }) {
  validateSchedule(payload?.scheduledPickupAt, nowMillis);
  const rideType = text(payload?.rideType, 80);
  const mode = payload?.mode;
  if (!rideType || !["quickSchedule", "chooseMyDriver"].includes(mode)) throw error("A valid rideType and mode are required", 422);
  await verifyRiderCanSchedule(db, riderId);
  await paymentVerifier({ riderId, authorization });
  const { pickup, dropoff, route } = await routeForPayload(payload, routeProvider);
  const candidates = await buildCandidateQuotes({
    db,
    rideType,
    pickup,
    dropoff,
    route,
    scheduledRideId: "preview",
    scheduledPickupMillis: timestampMillis(payload.scheduledPickupAt)
  });
  if (candidates.length === 0) throw error("No eligible scheduled drivers are available for this trip", 409);
  const totals = candidates.map((candidate) => candidate.quote.totalCents);
  return {
    pricingVersion: PRICING_VERSION,
    route: { distanceMiles: route.distanceMeters / 1609.344, durationMinutes: route.durationSeconds / 60 },
    suggestedLowCents: Math.min(...totals),
    suggestedHighCents: Math.max(...totals),
    eligibleDriverCount: candidates.length
  };
}

async function writeOpportunities({ db, requestRef, candidates, now }) {
  const batch = db.batch();
  candidates.forEach((candidate) => {
    batch.set(requestRef.collection("opportunities").doc(candidate.driverId), {
      ...candidate,
      status: "available",
      createdAt: now,
      updatedAt: now
    });
  });
  await batch.commit();
}

async function createScheduledRide({ riderId, authorization, payload, db = getFirestore(), routeProvider = getDirections, paymentVerifier = verifyPaymentReadiness, now = admin.firestore.Timestamp.now() }) {
  const pickupMillis = validateSchedule(payload?.scheduledPickupAt, now.toMillis());
  const rideType = text(payload?.rideType, 80);
  const mode = payload?.mode;
  const pickupName = text(payload?.pickup);
  const dropoffName = text(payload?.dropoff);
  const idempotencyKey = validIdempotencyKey(payload?.idempotencyKey);
  if (!rideType || !pickupName || !dropoffName || !idempotencyKey || !["quickSchedule", "chooseMyDriver"].includes(mode)) {
    throw error("pickup, dropoff, rideType, mode, and idempotencyKey are required", 422);
  }
  await verifyRiderCanSchedule(db, riderId);
  await paymentVerifier({ riderId, authorization });
  const idempotencyRef = db.collection("scheduledRideIdempotency").doc(`${riderId}_${idempotencyKey}`);
  const existing = await idempotencyRef.get();
  if (existing.exists) return { requestId: existing.data().requestId, duplicate: true };

  const requestRef = db.collection("scheduledRideRequests").doc();
  const { pickup, dropoff, route } = await routeForPayload(payload, routeProvider);
  const candidates = await buildCandidateQuotes({ db, rideType, pickup, dropoff, route, scheduledRideId: requestRef.id, scheduledPickupMillis: pickupMillis });
  if (candidates.length === 0) throw error("No eligible scheduled drivers are available for this trip", 409);
  const riderApprovedMaxCents = Math.round(Number(payload.riderApprovedMaxCents));
  if (mode === "quickSchedule" && (!Number.isFinite(riderApprovedMaxCents) || riderApprovedMaxCents <= 0)) {
    throw error("Quick Schedule requires an approved maximum price", 422);
  }
  const nowTimestamp = now;
  const scheduledPickupAt = admin.firestore.Timestamp.fromMillis(pickupMillis);
  const request = {
    id: requestRef.id,
    riderId,
    pickup: pickupName,
    dropoff: dropoffName,
    pickupCoordinate: { lat: pickup.latitude, lng: pickup.longitude },
    pickupGeoPoint: new admin.firestore.GeoPoint(pickup.latitude, pickup.longitude),
    dropoffCoordinate: { lat: dropoff.latitude, lng: dropoff.longitude },
    dropoffGeoPoint: new admin.firestore.GeoPoint(dropoff.latitude, dropoff.longitude),
    rideType,
    mode,
    status: "seekingDrivers",
    riderApprovedMaxCents: mode === "quickSchedule" ? riderApprovedMaxCents : null,
    riderPreferences: payload.riderPreferences && typeof payload.riderPreferences === "object" ? payload.riderPreferences : {},
    paymentReadinessVerifiedAt: nowTimestamp,
    pricingVersion: PRICING_VERSION,
    backendRouteProvider: "apple_maps",
    backendDistanceMeters: route.distanceMeters,
    backendDistanceMiles: route.distanceMeters / 1609.344,
    backendDurationSeconds: route.durationSeconds,
    backendDurationMinutes: route.durationSeconds / 60,
    scheduledPickupAt,
    opportunityCount: candidates.length,
    offerCount: 0,
    attemptedDriverIds: [],
    createdAt: nowTimestamp,
    updatedAt: nowTimestamp
  };
  Object.keys(request).forEach((key) => request[key] == null && delete request[key]);
  const creation = await db.runTransaction(async (tx) => {
    const duplicate = await tx.get(idempotencyRef);
    if (duplicate.exists) return { requestId: duplicate.data().requestId, duplicate: true };
    tx.create(requestRef, request);
    tx.create(idempotencyRef, { riderId, requestId: requestRef.id, createdAt: nowTimestamp });
    candidates.forEach((candidate) => {
      tx.create(requestRef.collection("opportunities").doc(candidate.driverId), {
        ...candidate,
        pickup: pickupName,
        dropoff: dropoffName,
        pickupCoordinate: { lat: pickup.latitude, lng: pickup.longitude },
        scheduledPickupAt,
        mode,
        status: "available",
        createdAt: nowTimestamp,
        updatedAt: nowTimestamp
      });
    });
    return { requestId: requestRef.id, duplicate: false };
  });
  if (creation.duplicate) return creation;
  if (pickupMillis - now.toMillis() <= DISPATCH_FALLBACK_LEAD_MS) {
    const fallback = await activateScheduledDispatchFallback({ requestId: requestRef.id, db, now });
    return {
      requestId: requestRef.id,
      duplicate: false,
      fallbackDispatch: true,
      request: requestPublicFields({
        ...request,
        status: fallback.status,
        activeRideId: fallback.rideId || null
      })
    };
  }
  return { requestId: requestRef.id, duplicate: false, request: requestPublicFields(request) };
}

async function createDriverLock({ tx, db, requestRef, request, driverId, now }) {
  const lockRef = db.collection("drivers").doc(driverId).collection("scheduledRideLocks").doc(requestRef.id);
  tx.set(lockRef, {
    scheduledRideId: requestRef.id,
    driverId,
    riderId: request.riderId,
    scheduledPickupAt: request.scheduledPickupAt,
    pickupCoordinate: request.pickupCoordinate,
    estimatedDurationMinutes: request.backendDurationMinutes,
    status: "active",
    createdAt: now,
    updatedAt: now
  });
}

async function closeRemainingOpportunities(requestRef, selectedDriverId, now) {
  const snapshot = await requestRef.collection("opportunities").where("status", "==", "available").get();
  if (snapshot.empty) return;
  const batch = requestRef.firestore.batch();
  snapshot.docs.forEach((doc) => {
    if (doc.id !== selectedDriverId) batch.set(doc.ref, { status: "closed", updatedAt: now }, { merge: true });
  });
  await batch.commit();
}

async function closeRemainingOffers(requestRef, selectedDriverId, now) {
  const snapshot = await requestRef.collection("offers").where("status", "==", "available").get();
  if (snapshot.empty) return;
  const batch = requestRef.firestore.batch();
  snapshot.docs.forEach((doc) => {
    if (doc.id !== selectedDriverId) batch.set(doc.ref, { status: "closed", updatedAt: now }, { merge: true });
  });
  await batch.commit();
}

async function respondToScheduledRide({ driverId, requestId, response, db = getFirestore(), now = admin.firestore.Timestamp.now() }) {
  if (!["accept", "decline"].includes(response)) throw error("response must be accept or decline", 422);
  const requestRef = db.collection("scheduledRideRequests").doc(requestId);
  const opportunityRef = requestRef.collection("opportunities").doc(driverId);
  const driverRef = db.collection("drivers").doc(driverId);
  const [requestSnap, opportunitySnap, driverSnap] = await Promise.all([
    requestRef.get(),
    opportunityRef.get(),
    driverRef.get()
  ]);
  if (!requestSnap.exists || !opportunitySnap.exists) throw error("Scheduled opportunity not found", 404);
  const request = requestSnap.data();
  if (opportunitySnap.data().status !== "available") throw error("This scheduled opportunity is no longer open", 409);
  if (!['seekingDrivers', 'awaitingRiderSelection', 'replacementSearching', 'replacementApprovalRequired'].includes(request.status)) {
    throw error("This scheduled opportunity is no longer open", 409);
  }
  if (response === "decline") {
    const batch = db.batch();
    batch.set(opportunityRef, { status: "declined", respondedAt: now, updatedAt: now }, { merge: true });
    batch.set(requestRef, {
      attemptedDriverIds: admin.firestore.FieldValue.arrayUnion(driverId),
      updatedAt: now
    }, { merge: true });
    await batch.commit();
    return { status: request.status };
  }
  if (!driverSnap.exists || !scheduledCandidateEligible(driverSnap.data(), request.rideType)) {
    throw error("This driver is no longer eligible for the scheduled ride", 403);
  }
  const opportunity = opportunitySnap.data();
  if (request.mode === "quickSchedule" && opportunity.quote.totalCents > request.riderApprovedMaxCents) {
    const batch = db.batch();
    batch.set(opportunityRef, { status: "outsideApprovedMaximum", respondedAt: now, updatedAt: now }, { merge: true });
    batch.set(requestRef, {
      attemptedDriverIds: admin.firestore.FieldValue.arrayUnion(driverId),
      updatedAt: now
    }, { merge: true });
    await batch.commit();
    throw error("This driver's price is above the rider's approved maximum", 409);
  }

  const result = await db.runTransaction(async (tx) => {
    const [currentSnap, currentOpportunitySnap, currentDriverSnap] = await Promise.all([
      tx.get(requestRef),
      tx.get(opportunityRef),
      tx.get(driverRef)
    ]);
    const current = currentSnap.data();
    if (!currentOpportunitySnap.exists || currentOpportunitySnap.data().status !== "available") {
      throw error("This scheduled opportunity is no longer open", 409);
    }
    if (!currentDriverSnap.exists || !scheduledCandidateEligible(currentDriverSnap.data(), current.rideType)) {
      throw error("This driver is no longer eligible for the scheduled ride", 403);
    }
    const currentOpportunity = currentOpportunitySnap.data();
    if (current.assignedDriverId) throw error("Another driver already accepted this scheduled ride", 409);
    if (current.mode === "quickSchedule" || current.replacementPolicy === "autoAssignFirstAcceptance") {
      const update = {
        status: "confirmed",
        assignedDriverId: driverId,
        acceptedOpportunityId: driverId,
        lockedPriceCents: currentOpportunity.quote.totalCents,
        lockedQuote: currentOpportunity.quote,
        lockedRates: currentOpportunity.rates,
        confirmedAt: now,
        replacementPolicy: admin.firestore.FieldValue.delete(),
        updatedAt: now
      };
      tx.set(requestRef, update, { merge: true });
      tx.set(opportunityRef, { status: "accepted", respondedAt: now, updatedAt: now }, { merge: true });
      await createDriverLock({ tx, db, requestRef, request: current, driverId, now });
      return { status: "confirmed", assignedDriverId: driverId };
    }

    if (Number(current.offerCount || 0) >= DRIVER_RESPONSE_LIMIT) {
      throw error("This scheduled ride already has three driver responses", 409);
    }
    const offerRef = requestRef.collection("offers").doc(driverId);
    const nextOfferCount = Math.min(DRIVER_RESPONSE_LIMIT, Number(current.offerCount || 0) + 1);
    tx.set(offerRef, { ...currentOpportunity, status: "available", offeredAt: now, updatedAt: now });
    tx.set(opportunityRef, { status: "responded", respondedAt: now, updatedAt: now }, { merge: true });
    tx.set(requestRef, { status: "awaitingRiderSelection", offerCount: nextOfferCount, updatedAt: now }, { merge: true });
    return { status: "awaitingRiderSelection", offerCount: nextOfferCount, offerLimitReached: nextOfferCount >= DRIVER_RESPONSE_LIMIT };
  });
  if (result.status === "confirmed") await closeRemainingOpportunities(requestRef, driverId, now);
  if (result.offerLimitReached) await closeRemainingOpportunities(requestRef, null, now);
  return result;
}

function onlineReadinessDeadlineMillis({ pickupMillis, etaSeconds }) {
  const travelLead = Math.max(
    MINIMUM_ONLINE_LEAD_MS,
    (Math.max(0, Number(etaSeconds) || 0) + ONLINE_ARRIVAL_BUFFER_SECONDS) * 1000
  );
  return pickupMillis - travelLead;
}

async function assignedDriverReadiness({ db, request, nowMillis, routeProvider = getDirections }) {
  const driverId = request.assignedDriverId;
  if (!driverId) return { online: false, etaSeconds: null };
  const [statusSnap, publicSnap] = await Promise.all([
    db.collection("driver_status").doc(driverId).get(),
    db.collection("publicDriverProfiles").doc(driverId).get()
  ]);
  const status = statusSnap.exists ? statusSnap.data() : {};
  const online = hasCurrentOnlinePresence(status, nowMillis);
  const location = status.location || (publicSnap.exists ? publicSnap.data().approximateLocation : null);
  if (!location) return { online, etaSeconds: null };
  try {
    const result = await routeProvider({
      origin: coordinate(location, "driverLocation"),
      destination: coordinate(request.pickupCoordinate, "pickupCoordinate"),
      departureDate: new Date(nowMillis).toISOString()
    });
    return { online, etaSeconds: Number(result.route?.durationSeconds || 0) || null };
  } catch {
    return { online, etaSeconds: null };
  }
}

async function startAutomaticReplacement({ db, requestRef, request, now, routeProvider = getDirections }) {
  const nowMillis = now.toMillis();
  const pickupMillis = timestampMillis(request.scheduledPickupAt);
  const previousDriverId = request.assignedDriverId;
  const excluded = [...new Set([...(request.attemptedDriverIds || []), previousDriverId].filter(Boolean))];
  if (previousDriverId) {
    await db.collection("drivers").doc(previousDriverId).collection("scheduledRideLocks").doc(requestRef.id)
      .set({ status: "replaced_unavailable", updatedAt: now }, { merge: true });
  }

  const pickup = coordinate(request.pickupCoordinate, "pickupCoordinate");
  const dropoff = coordinate(request.dropoffCoordinate, "dropoffCoordinate");
  const candidates = await buildCandidateQuotes({
    db,
    rideType: request.rideType,
    pickup,
    dropoff,
    route: { distanceMeters: request.backendDistanceMeters, durationSeconds: request.backendDurationSeconds },
    scheduledRideId: requestRef.id,
    scheduledPickupMillis: pickupMillis,
    excludedDriverIds: excluded,
    requireOnline: true,
    arriveByMillis: pickupMillis,
    rateOverride: request.lockedRates,
    quoteOverride: request.lockedQuote,
    routeProvider,
    nowMillis
  });
  if (candidates.length === 0 || !request.lockedQuote || !request.lockedRates) {
    await requestRef.set({
      status: "dispatchFallbackSearching",
      fallbackReason: "on_time_replacement_unavailable",
      fallbackSearchStartedAt: now,
      assignedDriverId: admin.firestore.FieldValue.delete(),
      attemptedDriverIds: excluded,
      updatedAt: now
    }, { merge: true });
    return "dispatchFallbackSearching";
  }

  const replacementCandidates = candidates.map((candidate) => ({
      ...candidate,
      pickup: request.pickup,
      dropoff: request.dropoff,
      pickupCoordinate: request.pickupCoordinate,
      scheduledPickupAt: request.scheduledPickupAt,
      mode: request.mode,
      lockedReplacementFare: true
    }));
  const batch = db.batch();
  replacementCandidates.forEach((candidate) => {
    batch.set(requestRef.collection("opportunities").doc(candidate.driverId), {
      ...candidate,
      status: "available",
      createdAt: now,
      updatedAt: now
    });
  });
  batch.set(requestRef, {
    status: "replacementSearching",
    replacementPolicy: "autoAssignFirstAcceptance",
    replacementReason: "assigned_driver_not_online_in_time",
    assignedDriverId: admin.firestore.FieldValue.delete(),
    acceptedOpportunityId: admin.firestore.FieldValue.delete(),
    attemptedDriverIds: excluded,
    replacementStartedAt: now,
    updatedAt: now
  }, { merge: true });
  await batch.commit();
  return "replacementSearching";
}

async function selectScheduledDriver({ riderId, requestId, driverId, db = getFirestore(), now = admin.firestore.Timestamp.now() }) {
  const requestRef = db.collection("scheduledRideRequests").doc(requestId);
  const offerRef = requestRef.collection("offers").doc(driverId);
  const driverRef = db.collection("drivers").doc(driverId);
  const result = await db.runTransaction(async (tx) => {
    const [requestSnap, offerSnap, driverSnap] = await Promise.all([
      tx.get(requestRef),
      tx.get(offerRef),
      tx.get(driverRef)
    ]);
    if (!requestSnap.exists || requestSnap.data().riderId !== riderId) throw error("Scheduled ride not found", 404);
    const request = requestSnap.data();
    if (!driverSnap.exists || !scheduledCandidateEligible(driverSnap.data(), request.rideType)) {
      throw error("That driver is no longer eligible for this scheduled ride", 409);
    }
    if (!["awaitingRiderSelection", "replacementApprovalRequired"].includes(request.status)) throw error("This ride is not awaiting a driver selection", 409);
    if (!offerSnap.exists || offerSnap.data().status !== "available") throw error("That driver offer is no longer available", 409);
    const offer = offerSnap.data();
    tx.set(requestRef, {
      status: "confirmed",
      assignedDriverId: driverId,
      acceptedOpportunityId: driverId,
      lockedPriceCents: offer.quote.totalCents,
      lockedQuote: offer.quote,
      lockedRates: offer.rates,
      confirmedAt: now,
      updatedAt: now
    }, { merge: true });
    tx.set(offerRef, { status: "selected", selectedAt: now, updatedAt: now }, { merge: true });
    await createDriverLock({ tx, db, requestRef, request, driverId, now });
    return { status: "confirmed", assignedDriverId: driverId, lockedPriceCents: offer.quote.totalCents };
  });
  await closeRemainingOpportunities(requestRef, driverId, now);
  await closeRemainingOffers(requestRef, driverId, now);
  return result;
}

async function checkInScheduledRide({ driverId, requestId, etaSeconds, db = getFirestore(), now = admin.firestore.Timestamp.now() }) {
  const eta = Math.round(Number(etaSeconds));
  if (!Number.isFinite(eta) || eta < 0 || eta > 4 * 60 * 60) throw error("A valid pickup ETA is required", 422);
  const requestRef = db.collection("scheduledRideRequests").doc(requestId);
  const snapshot = await requestRef.get();
  if (!snapshot.exists) throw error("Scheduled ride not found", 404);
  const request = snapshot.data();
  if (request.assignedDriverId !== driverId) throw error("This scheduled ride is assigned to another driver", 403);
  if (!["confirmed", "checkInRequired", "checkedIn"].includes(request.status)) throw error("This scheduled ride cannot be checked in", 409);
  const pickupMillis = timestampMillis(request.scheduledPickupAt);
  const activationMillis = pickupMillis - ((eta + ACTIVATION_BUFFER_SECONDS) * 1000);
  const update = {
    status: "checkedIn",
    driverCheckInAt: now,
    driverPickupEtaSeconds: eta,
    activationAt: admin.firestore.Timestamp.fromMillis(activationMillis),
    updatedAt: now
  };
  await requestRef.set(update, { merge: true });
  return requestPublicFields({ ...request, ...update });
}

async function cancelScheduledRide({ uid, requestId, reason, db = getFirestore(), now = admin.firestore.Timestamp.now() }) {
  const requestRef = db.collection("scheduledRideRequests").doc(requestId);
  const snapshot = await requestRef.get();
  if (!snapshot.exists) throw error("Scheduled ride not found", 404);
  const request = snapshot.data();
  const isRider = request.riderId === uid;
  const isDriver = request.assignedDriverId === uid;
  if (!isRider && !isDriver) throw error("This scheduled ride does not belong to this user", 403);
  if (["active", "completed", "cancelled"].includes(request.status)
      || (request.status === "expired" && !isRider)) {
    throw error("This scheduled ride can no longer be cancelled here", 409);
  }

  if (isRider) {
    const pastDueUndispatched = isPastDueUndispatchedScheduledRide(request, now.toMillis());
    const update = {
      status: "cancelled",
      cancelledByRole: "rider",
      cancellationReason: text(reason, 500),
      cancelledAt: now,
      updatedAt: now
    };
    if (pastDueUndispatched) update.riderArchivedAt = now;
    await requestRef.set(update, { merge: true });
    if (request.assignedDriverId) {
      await db.collection("drivers").doc(request.assignedDriverId).collection("scheduledRideLocks").doc(requestId)
        .set({ status: "cancelled", updatedAt: now }, { merge: true });
    }
    await closeRemainingOpportunities(requestRef, null, now);
    await closeRemainingOffers(requestRef, null, now);
    return { status: "cancelled", archived: pastDueUndispatched, cancellationFeeCents: 0 };
  }

  const excluded = [...new Set([...(request.attemptedDriverIds || []), uid])];
  await db.collection("drivers").doc(uid).collection("scheduledRideLocks").doc(requestId)
    .set({ status: "released", updatedAt: now }, { merge: true });
  const pickup = coordinate(request.pickupCoordinate, "pickupCoordinate");
  const dropoff = coordinate(request.dropoffCoordinate, "dropoffCoordinate");
  const route = { distanceMeters: request.backendDistanceMeters, durationSeconds: request.backendDurationSeconds };
  const candidates = await buildCandidateQuotes({
    db,
    rideType: request.rideType,
    pickup,
    dropoff,
    route,
    scheduledRideId: requestId,
    scheduledPickupMillis: timestampMillis(request.scheduledPickupAt),
    excludedDriverIds: excluded
  });
  const withinWindow = (timestampMillis(request.scheduledPickupAt) - now.toMillis()) > REPLACEMENT_CUTOFF_MS;
  if (candidates.length === 0 || !withinWindow) {
    await requestRef.set({ status: "expired", terminalReason: "replacement_unavailable", attemptedDriverIds: excluded, updatedAt: now }, { merge: true });
    return { status: "expired" };
  }
  await writeOpportunities({
    db,
    requestRef,
    candidates: candidates.map((candidate) => ({
      ...candidate,
      pickup: request.pickup,
      dropoff: request.dropoff,
      pickupCoordinate: request.pickupCoordinate,
      scheduledPickupAt: request.scheduledPickupAt,
      mode: request.mode
    })),
    now
  });
  await requestRef.set({
    status: request.mode === "quickSchedule" ? "replacementSearching" : "replacementApprovalRequired",
    assignedDriverId: admin.firestore.FieldValue.delete(),
    acceptedOpportunityId: admin.firestore.FieldValue.delete(),
    lockedPriceCents: admin.firestore.FieldValue.delete(),
    lockedQuote: admin.firestore.FieldValue.delete(),
    lockedRates: admin.firestore.FieldValue.delete(),
    offerCount: 0,
    attemptedDriverIds: excluded,
    replacementStartedAt: now,
    updatedAt: now
  }, { merge: true });
  return { status: request.mode === "quickSchedule" ? "replacementSearching" : "replacementApprovalRequired" };
}

async function activateScheduledRide({ requestId, db = getFirestore(), now = admin.firestore.Timestamp.now() }) {
  const requestRef = db.collection("scheduledRideRequests").doc(requestId);
  const snapshot = await requestRef.get();
  if (!snapshot.exists) throw error("Scheduled ride not found", 404);
  const request = snapshot.data();
  if (request.status === "active" && request.activeRideId) return { status: "active", rideId: request.activeRideId, duplicate: true };
  if (request.status !== "checkedIn" || !request.assignedDriverId) throw error("Scheduled ride is not ready to activate", 409);
  await requestRef.set({ status: "activating", updatedAt: now }, { merge: true });
  try {
    const result = await createRideRequest({
      riderId: request.riderId,
      payload: {
        idempotencyKey: `scheduled_${requestId}`,
        selectedCandidateId: request.assignedDriverId,
        candidateDriverIds: [request.assignedDriverId],
        pickup: request.pickup,
        dropoff: request.dropoff,
        pickupCoordinate: request.pickupCoordinate,
        dropoffCoordinate: request.dropoffCoordinate,
        rideType: request.rideType,
        ridePreferences: request.riderPreferences,
        source: "scheduledRydr",
        scheduledRideId: requestId
      },
      db,
      paymentVerifier: async () => true,
      authUserProvider: async (uid) => admin.auth().getUser(uid),
      authoritativeRateOverride: request.lockedRates,
      authoritativeRouteOverride: {
        name: "Scheduled locked route",
        distanceMeters: request.backendDistanceMeters,
        durationSeconds: request.backendDurationSeconds,
        hasTolls: null,
        transportType: "AUTOMOBILE"
      },
      trustedScheduledActivation: true,
      now
    });
    await requestRef.set({ status: "active", activeRideId: result.rideId, activatedAt: now, updatedAt: now }, { merge: true });
    return { status: "active", rideId: result.rideId, duplicate: result.duplicate };
  } catch (activationError) {
    await requestRef.set({ status: "checkedIn", activationError: activationError.message, updatedAt: now }, { merge: true });
    throw activationError;
  }
}

async function activateScheduledDispatchFallback({ requestId, db = getFirestore(), now = admin.firestore.Timestamp.now() }) {
  const requestRef = db.collection("scheduledRideRequests").doc(requestId);
  const snapshot = await requestRef.get();
  if (!snapshot.exists) throw error("Scheduled ride not found", 404);
  const request = snapshot.data();
  if (request.status === "active" && request.activeRideId) {
    return { status: "active", rideId: request.activeRideId, duplicate: true };
  }
  const pickupMillis = timestampMillis(request.scheduledPickupAt);
  if (pickupMillis == null) throw error("Scheduled pickup time is unavailable", 409);
  if (now.toMillis() > pickupMillis + DISPATCH_FALLBACK_WINDOW_MS) {
    await requestRef.set({
      status: "expired",
      terminalReason: "dispatch_fallback_window_elapsed",
      updatedAt: now
    }, { merge: true });
    return { status: "expired", rideId: null };
  }

  const pickup = coordinate(request.pickupCoordinate, "pickupCoordinate");
  const dropoff = coordinate(request.dropoffCoordinate, "dropoffCoordinate");
  const route = { distanceMeters: request.backendDistanceMeters, durationSeconds: request.backendDurationSeconds };
  const candidates = (await buildCandidateQuotes({
    db,
    rideType: request.rideType,
    pickup,
    dropoff,
    route,
    scheduledRideId: requestId,
    scheduledPickupMillis: pickupMillis,
    excludedDriverIds: request.attemptedDriverIds || [],
    requireOnline: true,
    nowMillis: now.toMillis()
  })).sort((left, right) => left.distanceToPickupMiles - right.distanceToPickupMiles);

  if (candidates.length === 0) {
    await requestRef.set({
      status: "dispatchFallbackSearching",
      fallbackReason: "scheduled_ride_unassigned_at_pickup",
      fallbackSearchStartedAt: request.fallbackSearchStartedAt || now,
      assignedDriverId: admin.firestore.FieldValue.delete(),
      updatedAt: now
    }, { merge: true });
    await closeRemainingOpportunities(requestRef, null, now);
    await closeRemainingOffers(requestRef, null, now);
    return { status: "dispatchFallbackSearching", rideId: null };
  }

  const firstCandidate = candidates[0];
  await requestRef.set({ status: "dispatchFallbackActivating", updatedAt: now }, { merge: true });
  try {
    const result = await createRideRequest({
      riderId: request.riderId,
      payload: {
        idempotencyKey: `scheduled_${requestId}`,
        selectedCandidateId: firstCandidate.driverId,
        candidateDriverIds: candidates.map((candidate) => candidate.driverId),
        pickup: request.pickup,
        dropoff: request.dropoff,
        pickupCoordinate: request.pickupCoordinate,
        dropoffCoordinate: request.dropoffCoordinate,
        rideType: request.rideType,
        ridePreferences: request.riderPreferences,
        source: "scheduledRydr",
        scheduledRideId: requestId
      },
      db,
      paymentVerifier: async () => true,
      authUserProvider: async (uid) => admin.auth().getUser(uid),
      authoritativeRateOverride: firstCandidate.rates,
      authoritativeRouteOverride: {
        name: "Scheduled dispatch fallback route",
        distanceMeters: request.backendDistanceMeters,
        durationSeconds: request.backendDurationSeconds,
        hasTolls: null,
        transportType: "AUTOMOBILE"
      },
      trustedScheduledActivation: true,
      now
    });
    await requestRef.set({
      status: "active",
      activeRideId: result.rideId,
      assignedDriverId: admin.firestore.FieldValue.delete(),
      fallbackDispatchedAt: now,
      fallbackReason: "scheduled_ride_unassigned_at_pickup",
      updatedAt: now
    }, { merge: true });
    await closeRemainingOpportunities(requestRef, firstCandidate.driverId, now);
    await closeRemainingOffers(requestRef, null, now);
    return { status: "active", rideId: result.rideId, duplicate: result.duplicate };
  } catch (fallbackError) {
    await requestRef.set({
      status: "dispatchFallbackSearching",
      fallbackActivationError: fallbackError.message,
      updatedAt: now
    }, { merge: true });
    return { status: "dispatchFallbackSearching", rideId: null };
  }
}

async function sweepScheduledRides({ db = getFirestore(), now = admin.firestore.Timestamp.now(), routeProvider = getDirections }) {
  const nowMillis = now.toMillis();
  const snapshot = await db.collection("scheduledRideRequests")
    .where("status", "in", ["confirmed", "checkInRequired", "checkedIn", "seekingDrivers", "awaitingRiderSelection", "replacementSearching", "replacementApprovalRequired", "dispatchFallbackSearching", "dispatchFallbackActivating"])
    .limit(200)
    .get();
  const results = [];
  for (const doc of snapshot.docs) {
    const request = doc.data();
    const pickupMillis = timestampMillis(request.scheduledPickupAt);
    if (!pickupMillis) continue;
    if (["confirmed", "checkInRequired"].includes(request.status)
        && request.assignedDriverId
        && nowMillis >= pickupMillis - ONLINE_READINESS_WINDOW_MS) {
      const readiness = await assignedDriverReadiness({ db, request, nowMillis, routeProvider });
      const deadline = onlineReadinessDeadlineMillis({ pickupMillis, etaSeconds: readiness.etaSeconds });
      const cannotArriveOnTime = readiness.etaSeconds != null
        && nowMillis + (readiness.etaSeconds + ONLINE_ARRIVAL_BUFFER_SECONDS) * 1000 > pickupMillis;
      const readinessCannotBeProven = readiness.etaSeconds == null
        && nowMillis >= pickupMillis - MINIMUM_ONLINE_LEAD_MS;
      if (cannotArriveOnTime || readinessCannotBeProven || (!readiness.online && nowMillis >= deadline)) {
        const action = await startAutomaticReplacement({ db, requestRef: doc.ref, request, now, routeProvider });
        results.push({ requestId: doc.id, action });
        continue;
      }
    }
    if (["seekingDrivers", "awaitingRiderSelection", "replacementSearching", "replacementApprovalRequired", "dispatchFallbackSearching", "dispatchFallbackActivating"].includes(request.status)
        && nowMillis >= pickupMillis - DISPATCH_FALLBACK_LEAD_MS) {
      const fallback = await activateScheduledDispatchFallback({ requestId: doc.id, db, now });
      results.push({ requestId: doc.id, action: fallback.status });
      continue;
    }
    if (request.status === "confirmed" && nowMillis >= pickupMillis - CHECK_IN_LEAD_MS) {
      await doc.ref.set({ status: "checkInRequired", updatedAt: now }, { merge: true });
      results.push({ requestId: doc.id, action: "checkInRequired" });
    } else if (request.status === "checkedIn" && timestampMillis(request.activationAt) <= nowMillis) {
      await activateScheduledRide({ requestId: doc.id, db, now });
      results.push({ requestId: doc.id, action: "activated" });
    } else if (["confirmed", "checkInRequired"].includes(request.status) && nowMillis >= pickupMillis - CHECK_IN_CUTOFF_MS) {
      if (request.assignedDriverId) {
        await db.collection("drivers").doc(request.assignedDriverId).collection("scheduledRideLocks").doc(doc.id)
          .set({ status: "released_to_dispatch_fallback", updatedAt: now }, { merge: true });
      }
      await doc.ref.set({
        status: "dispatchFallbackSearching",
        fallbackReason: "driver_missed_check_in",
        assignedDriverId: admin.firestore.FieldValue.delete(),
        updatedAt: now
      }, { merge: true });
      results.push({ requestId: doc.id, action: "dispatchFallbackSearching" });
    } else if (nowMillis >= pickupMillis) {
      const fallback = await activateScheduledDispatchFallback({ requestId: doc.id, db, now });
      results.push({ requestId: doc.id, action: fallback.status });
    }
  }
  return { processed: snapshot.size, changes: results };
}

module.exports = {
  MINIMUM_LEAD_TIME_MS,
  MAXIMUM_LEAD_TIME_MS,
  ACTIVATION_BUFFER_SECONDS,
  ONLINE_READINESS_WINDOW_MS,
  MINIMUM_ONLINE_LEAD_MS,
  ONLINE_ARRIVAL_BUFFER_SECONDS,
  DISPATCH_FALLBACK_WINDOW_MS,
  DISPATCH_FALLBACK_LEAD_MS,
  DRIVER_RESPONSE_LIMIT,
  validateSchedule,
  scheduledCandidateEligible,
  quoteFor,
  onlineReadinessDeadlineMillis,
  isPastDueUndispatchedScheduledRide,
  previewScheduledRide,
  createScheduledRide,
  respondToScheduledRide,
  selectScheduledDriver,
  checkInScheduledRide,
  cancelScheduledRide,
  activateScheduledRide,
  activateScheduledDispatchFallback,
  sweepScheduledRides
};
