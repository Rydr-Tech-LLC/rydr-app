import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue, Timestamp } from "../admin";
import {
  ScheduledRideQuote,
  ScheduledRideSelectionMode,
  ScheduledRideTierId,
  ScheduledRidesConfig,
  canonicalRideType,
  isSelectionMode,
  maximumScheduledRideQuote,
  minimumScheduledRideQuote,
  calculateScheduledRideQuote,
  scheduleLockBucketId,
  scheduleLockWindow,
  scheduledRidesConfigFromData
} from "./domain";

type Data = Record<string, unknown>;

interface ValidatedRequestInput {
  requestId: string;
  selectionMode: ScheduledRideSelectionMode;
  rideType: ScheduledRideTierId;
  pickup: Data;
  destination: Data;
  routeEstimate: { distanceMiles: number; durationMinutes: number; source: string; version: string };
  scheduledAtMs: number;
  timeZone: string;
  approvedMaximumCents: number;
  preferences: Data;
}

const CONFIG_REF = () => db.collection("platformConfig").doc("scheduledRides");
const requests = () => db.collection("scheduledRideRequests");
const opportunities = () => db.collection("scheduledRideOpportunities");

function object(value: unknown, name: string): Data {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${name} must be an object.`);
  }
  return value as Data;
}

function finite(value: unknown, name: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
    throw new HttpsError("invalid-argument", `${name} must be between ${min} and ${max}.`);
  }
  return value;
}

function string(value: unknown, name: string, max = 200): string {
  if (typeof value !== "string" || value.trim().length === 0 || value.trim().length > max) {
    throw new HttpsError("invalid-argument", `${name} is required.`);
  }
  return value.trim();
}

function assertOnlyKeys(data: Data, allowed: string[]): void {
  const extras = Object.keys(data).filter((key) => !allowed.includes(key));
  if (extras.length > 0) {
    throw new HttpsError("invalid-argument", `Unsupported fields: ${extras.join(", ")}.`);
  }
}

function validTimeZone(value: unknown): string {
  const zone = string(value, "timeZone", 100);
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone }).format();
  } catch {
    throw new HttpsError("invalid-argument", "timeZone must be a valid IANA time zone.");
  }
  return zone;
}

function validatePlace(value: unknown, name: string): Data {
  const place = object(value, name);
  assertOnlyKeys(place, ["address", "latitude", "longitude", "area"]);
  return {
    address: string(place.address, `${name}.address`, 500),
    latitude: finite(place.latitude, `${name}.latitude`, -90, 90),
    longitude: finite(place.longitude, `${name}.longitude`, -180, 180),
    area: typeof place.area === "string" ? place.area.trim().slice(0, 120) : ""
  };
}

function validatePreferences(value: unknown): Data {
  if (value === undefined) return { requiredCapabilities: [], requiredVehicleAttributes: {}, allowAutomaticReplacement: false };
  const preferences = object(value, "preferences");
  assertOnlyKeys(preferences, ["requiredCapabilities", "requiredVehicleAttributes", "allowAutomaticReplacement"]);
  const capabilities = preferences.requiredCapabilities === undefined ? [] : preferences.requiredCapabilities;
  if (!Array.isArray(capabilities) || capabilities.length > 10 || capabilities.some((item) => typeof item !== "string" || item.trim().length === 0 || item.length > 80)) {
    throw new HttpsError("invalid-argument", "preferences.requiredCapabilities must contain at most 10 capability names.");
  }
  const attributes = preferences.requiredVehicleAttributes === undefined
    ? {}
    : object(preferences.requiredVehicleAttributes, "preferences.requiredVehicleAttributes");
  if (Object.keys(attributes).length > 10 || Object.entries(attributes).some(([key, item]) => {
    return key.length === 0 || key.length > 80 || !(typeof item === "string" || typeof item === "boolean");
  })) {
    throw new HttpsError("invalid-argument", "preferences.requiredVehicleAttributes contains unsupported values.");
  }
  if (preferences.allowAutomaticReplacement !== undefined && typeof preferences.allowAutomaticReplacement !== "boolean") {
    throw new HttpsError("invalid-argument", "preferences.allowAutomaticReplacement must be a boolean.");
  }
  return {
    requiredCapabilities: Array.from(new Set((capabilities as string[]).map((item) => item.trim()))),
    requiredVehicleAttributes: attributes,
    allowAutomaticReplacement: preferences.allowAutomaticReplacement === true
  };
}

async function loadConfig(uid: string, role: "rider" | "driver"): Promise<ScheduledRidesConfig> {
  const snapshot = await CONFIG_REF().get();
  const config = scheduledRidesConfigFromData(snapshot.exists ? snapshot.data() : undefined);
  if (!config.enabled) throw new HttpsError("failed-precondition", "Scheduled rides are not enabled.");
  const allowlist = role === "rider" ? config.allowedRiderIds : config.allowedDriverIds;
  if (allowlist.length > 0 && !allowlist.includes(uid)) {
    throw new HttpsError("permission-denied", "Scheduled rides are not enabled for this account.");
  }
  return config;
}

function validateRequestInput(
  value: unknown,
  config: ScheduledRidesConfig,
  nowMs: number,
  requireApprovedMaximum: boolean
): ValidatedRequestInput {
  const data = object(value, "request");
  assertOnlyKeys(data, [
    "requestId", "selectionMode", "rideType", "pickup", "destination", "routeEstimate",
    "scheduledAtEpochMs", "timeZone", "approvedMaximumCents", "preferences"
  ]);
  const requestId = string(data.requestId, "requestId", 100);
  if (!/^[A-Za-z0-9_-]{12,100}$/.test(requestId)) {
    throw new HttpsError("invalid-argument", "requestId must be a 12-100 character safe identifier.");
  }
  if (!isSelectionMode(data.selectionMode)) throw new HttpsError("invalid-argument", "selectionMode is invalid.");
  const rideType = typeof data.rideType === "string" ? canonicalRideType(data.rideType) : null;
  if (!rideType || !config.allowedRideTypes.includes(rideType)) {
    throw new HttpsError("invalid-argument", "rideType is not enabled for scheduled rides.");
  }
  const estimateData = object(data.routeEstimate, "routeEstimate");
  assertOnlyKeys(estimateData, ["distanceMiles", "durationMinutes", "source", "version"]);
  const routeEstimate = {
    distanceMiles: finite(estimateData.distanceMiles, "routeEstimate.distanceMiles", 0.01, 500),
    durationMinutes: finite(estimateData.durationMinutes, "routeEstimate.durationMinutes", 0.01, 1440),
    source: string(estimateData.source, "routeEstimate.source", 80),
    version: string(estimateData.version, "routeEstimate.version", 80)
  };
  const scheduledAtMs = finite(data.scheduledAtEpochMs, "scheduledAtEpochMs", 0, 9_000_000_000_000);
  const earliest = nowMs + config.minimumLeadMinutes * 60_000;
  const latest = nowMs + config.maximumAdvanceDays * 86_400_000;
  if (scheduledAtMs < earliest || scheduledAtMs > latest) {
    throw new HttpsError("failed-precondition", "Pickup time is outside the configured scheduling window.");
  }
  return {
    requestId,
    selectionMode: data.selectionMode,
    rideType,
    pickup: validatePlace(data.pickup, "pickup"),
    destination: validatePlace(data.destination, "destination"),
    routeEstimate,
    scheduledAtMs,
    timeZone: validTimeZone(data.timeZone),
    approvedMaximumCents: data.approvedMaximumCents === undefined && !requireApprovedMaximum
      ? 0
      : finite(data.approvedMaximumCents, "approvedMaximumCents", 1, 10_000_000),
    preferences: validatePreferences(data.preferences)
  };
}

function quoteRange(input: ValidatedRequestInput, config: ScheduledRidesConfig) {
  const tier = config.pricingTiers[input.rideType];
  return {
    minimum: minimumScheduledRideQuote(input.routeEstimate, tier, config.pricingVersion, config.driverPayoutBasisPoints),
    maximum: maximumScheduledRideQuote(input.routeEstimate, tier, config.pricingVersion, config.driverPayoutBasisPoints)
  };
}

export async function previewScheduledRidePriceForUser(uid: string, raw: unknown): Promise<Data> {
  const config = await loadConfig(uid, "rider");
  const input = validateRequestInput(raw, config, Date.now(), false);
  const range = quoteRange(input, config);
  return { rideType: input.rideType, pricingVersion: config.pricingVersion, minimum: range.minimum, maximum: range.maximum };
}

export async function createScheduledRideRequestForUser(uid: string, raw: unknown, nowMs = Date.now()): Promise<Data> {
  const config = await loadConfig(uid, "rider");
  const input = validateRequestInput(raw, config, nowMs, true);
  const range = quoteRange(input, config);
  if (input.approvedMaximumCents !== range.maximum.riderBaseFareCents) {
    throw new HttpsError("failed-precondition", "Approved maximum does not match the current server quote.");
  }
  const requestRef = requests().doc(input.requestId);
  const opportunityRef = opportunities().doc(input.requestId);
  const scheduledAt = Timestamp.fromMillis(input.scheduledAtMs);
  const offerClosesAtMs = Math.min(input.scheduledAtMs, nowMs + config.offerWindowMinutes * 60_000);
  const selectionClosesAtMs = Math.min(input.scheduledAtMs, offerClosesAtMs + config.riderSelectionWindowMinutes * 60_000);

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(requestRef);
    if (existing.exists) {
      if (existing.get("riderId") !== uid) throw new HttpsError("already-exists", "requestId is already in use.");
      return { requestId: input.requestId, status: existing.get("status"), idempotent: true };
    }
    const base = {
      schemaVersion: config.schemaVersion,
      requestId: input.requestId,
      riderId: uid,
      selectionMode: input.selectionMode,
      rideType: input.rideType,
      pickup: input.pickup,
      destination: input.destination,
      routeEstimate: input.routeEstimate,
      scheduledAt,
      originalTimeZone: input.timeZone,
      preferences: input.preferences,
      status: "seekingDrivers",
      activeOfferCount: 0,
      offerDriverIds: [],
      assignedDriverId: null,
      priceLockId: null,
      resultingRideId: null,
      approvedMaximumCents: range.maximum.riderBaseFareCents,
      minimumQuoteCents: range.minimum.riderBaseFareCents,
      currency: "usd",
      pricingVersion: config.pricingVersion,
      offerClosesAt: Timestamp.fromMillis(offerClosesAtMs),
      selectionClosesAt: Timestamp.fromMillis(selectionClosesAtMs),
      checkInDueAt: Timestamp.fromMillis(input.scheduledAtMs - config.driverCheckInLeadMinutes * 60_000),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp()
    };
    tx.create(requestRef, base);
    tx.create(opportunityRef, {
      schemaVersion: config.schemaVersion,
      requestId: input.requestId,
      selectionMode: input.selectionMode,
      rideType: input.rideType,
      pickupArea: input.pickup.area,
      pickupLatitudeBucket: Math.round((input.pickup.latitude as number) * 100) / 100,
      pickupLongitudeBucket: Math.round((input.pickup.longitude as number) * 100) / 100,
      scheduledAt,
      routeEstimate: input.routeEstimate,
      preferences: input.preferences,
      approvedMaximumCents: range.maximum.riderBaseFareCents,
      currency: "usd",
      status: "open",
      offerClosesAt: Timestamp.fromMillis(offerClosesAtMs),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp()
    });
    return { requestId: input.requestId, status: "seekingDrivers", approvedMaximumCents: range.maximum.riderBaseFareCents };
  });
}

function stringsFrom(data: Data, names: string[]): string[] {
  for (const name of names) {
    if (Array.isArray(data[name])) return (data[name] as unknown[]).filter((v): v is string => typeof v === "string");
  }
  return [];
}

function driverIsApproved(data: Data): boolean {
  const approval = data.driverApprovalStatus ?? data.approvalStatus;
  return (approval === "approved" || data.isApproved === true) && data.suspended !== true && data.safetyHold !== true;
}

function driverSupports(data: Data, rideType: ScheduledRideTierId): boolean {
  return stringsFrom(data, ["selectedRideTypes", "qualifiedRideTypes", "supportedRideTypes", "rideTypes"])
    .some((value) => canonicalRideType(value) === rideType);
}

function driverMeetsPreferences(driver: Data, publicProfile: Data, preferences: Data): boolean {
  const requiredCapabilities = Array.isArray(preferences.requiredCapabilities)
    ? preferences.requiredCapabilities as string[]
    : [];
  const capabilities = new Set([
    ...stringsFrom(driver, ["capabilities"]),
    ...stringsFrom(publicProfile, ["capabilities"])
  ].map((item) => item.toLowerCase()));
  if (requiredCapabilities.some((item) => !capabilities.has(item.toLowerCase()))) return false;

  const requiredAttributes = preferences.requiredVehicleAttributes && typeof preferences.requiredVehicleAttributes === "object"
    ? preferences.requiredVehicleAttributes as Data
    : {};
  const vehicle = publicProfile.vehicle && typeof publicProfile.vehicle === "object"
    ? publicProfile.vehicle as Data
    : driver.vehicle && typeof driver.vehicle === "object" ? driver.vehicle as Data : {};
  return Object.entries(requiredAttributes).every(([key, value]) => vehicle[key] === value);
}

function driverRateCents(data: Data, rideType: ScheduledRideTierId): { perMile: number; perMinute: number } {
  const rates = object(data.tierRates, "driver.tierRates");
  const entry = Object.entries(rates).find(([key]) => canonicalRideType(key) === rideType)?.[1];
  const rate = object(entry, `driver.tierRates.${rideType}`);
  return {
    perMile: Math.round(finite(rate.perMile, "driver per-mile rate", 0, 100) * 100),
    perMinute: Math.round(finite(rate.perMinute, "driver per-minute rate", 0, 100) * 100)
  };
}

function driverSnapshot(driverId: string, driver: Data, publicProfile: Data): Data {
  const vehicle = (publicProfile.vehicle && typeof publicProfile.vehicle === "object" ? publicProfile.vehicle : driver.vehicle) ?? {};
  return {
    driverId,
    displayName: publicProfile.displayName ?? driver.displayName ?? "Driver",
    photoURL: publicProfile.photoURL ?? publicProfile.profileImageURL ?? null,
    rating: publicProfile.rating ?? driver.rating ?? null,
    vehicle
  };
}

function rateSnapshot(quote: ScheduledRideQuote): Data {
  return {
    pricingVersion: quote.pricingVersion,
    perMileCents: quote.driverRatePerMileCents,
    perMinuteCents: quote.driverRatePerMinuteCents,
    capturedAt: FieldValue.serverTimestamp()
  };
}

function priceLockData(requestId: string, riderId: string, driverId: string, offerId: string, request: Data, quote: ScheduledRideQuote): Data {
  return {
    schemaVersion: request.schemaVersion,
    requestId,
    riderId,
    driverId,
    offerId,
    pricingVersion: quote.pricingVersion,
    routeEstimate: request.routeEstimate,
    rateSnapshot: rateSnapshot(quote),
    quote,
    lockedBaseFareCents: quote.riderBaseFareCents,
    approvedMaximumCents: request.approvedMaximumCents,
    currency: "usd",
    immutable: true,
    approvedAt: FieldValue.serverTimestamp()
  };
}

async function readLockSnapshots(
  tx: admin.firestore.Transaction,
  driverId: string,
  request: Data,
  config: ScheduledRidesConfig
) {
  const scheduledAt = request.scheduledAt as admin.firestore.Timestamp;
  const estimate = request.routeEstimate as { durationMinutes: number };
  const window = scheduleLockWindow(scheduledAt.toMillis(), estimate.durationMinutes, config);
  const refs = window.bucketStartsAtMs.map((ms) => db.collection("drivers").doc(driverId).collection("scheduledRideLocks").doc(scheduleLockBucketId(ms)));
  const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
  if (snapshots.some((snapshot) => snapshot.exists && snapshot.get("requestId") !== request.requestId)) {
    throw new HttpsError("failed-precondition", "Driver has a conflicting scheduled ride.");
  }
  return { window, refs };
}

function writeLocks(
  tx: admin.firestore.Transaction,
  refs: admin.firestore.DocumentReference[],
  request: Data,
  driverId: string,
  startsAtMs: number,
  endsAtMs: number
): void {
  refs.forEach((ref) => tx.create(ref, {
    requestId: request.requestId,
    driverId,
    scheduledAt: request.scheduledAt,
    startsAt: Timestamp.fromMillis(startsAtMs),
    endsAt: Timestamp.fromMillis(endsAtMs),
    status: "reserved",
    createdAt: FieldValue.serverTimestamp()
  }));
}

export async function respondToScheduledRideForUser(uid: string, raw: unknown): Promise<Data> {
  const config = await loadConfig(uid, "driver");
  const input = object(raw, "response");
  assertOnlyKeys(input, ["requestId"]);
  const requestId = string(input.requestId, "requestId", 100);
  const requestRef = requests().doc(requestId);
  const offerRef = requestRef.collection("offers").doc(uid);
  const driverRef = db.collection("drivers").doc(uid);
  const statusRef = db.collection("driver_status").doc(uid);
  const profileRef = db.collection("publicDriverProfiles").doc(uid);

  return db.runTransaction(async (tx) => {
    const [requestSnap, driverSnap, statusSnap, profileSnap, existingOffer] = await Promise.all([
      tx.get(requestRef), tx.get(driverRef), tx.get(statusRef), tx.get(profileRef), tx.get(offerRef)
    ]);
    if (!requestSnap.exists) throw new HttpsError("not-found", "Scheduled ride request was not found.");
    if (existingOffer.exists) return { requestId, offerId: uid, status: existingOffer.get("status"), idempotent: true };
    const request = requestSnap.data() as Data;
    const driver = (driverSnap.data() ?? {}) as Data;
    const acceptingOffers = request.selectionMode === "chooseDriver"
      ? ["seekingDrivers", "awaitingRiderSelection"].includes(String(request.status))
      : request.status === "seekingDrivers";
    if (!acceptingOffers || (request.offerClosesAt as admin.firestore.Timestamp).toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "This scheduled opportunity is closed.");
    }
    const rideType = canonicalRideType(String(request.rideType));
    const publicProfile = (profileSnap.data() ?? {}) as Data;
    if (!rideType || !driverIsApproved(driver) || !driverSupports(driver, rideType) || !driverMeetsPreferences(driver, publicProfile, request.preferences as Data)) {
      throw new HttpsError("permission-denied", "Driver is not eligible for this scheduled ride.");
    }
    if (statusSnap.exists && statusSnap.get("hasActiveRide") === true) {
      throw new HttpsError("failed-precondition", "Driver currently has an active ride.");
    }
    const rates = driverRateCents(driver, rideType);
    const tier = config.pricingTiers[rideType];
    if (
      rates.perMile < tier.minPerMileCents || rates.perMile > tier.maxPerMileCents ||
      rates.perMinute < tier.minPerMinuteCents || rates.perMinute > tier.maxPerMinuteCents
    ) {
      throw new HttpsError("failed-precondition", "Driver rates are outside the configured limits.");
    }
    const quote = calculateScheduledRideQuote(
      request.routeEstimate as { distanceMiles: number; durationMinutes: number; source: string; version: string },
      tier, rates.perMile, rates.perMinute, config.pricingVersion, config.driverPayoutBasisPoints
    );
    if (quote.riderBaseFareCents > Number(request.approvedMaximumCents)) {
      throw new HttpsError("failed-precondition", "Driver rate exceeds the rider-approved maximum.");
    }
    const isQuick = request.selectionMode === "quick";
    const count = Number(request.activeOfferCount ?? 0);
    if (!isQuick && count >= config.maximumOffers) throw new HttpsError("resource-exhausted", "The offer limit has been reached.");
    const lock = isQuick ? await readLockSnapshots(tx, uid, request, config) : null;
    const snapshot = driverSnapshot(uid, driver, publicProfile);
    tx.create(offerRef, {
      requestId, driverId: uid, status: isQuick ? "selected" : "active", driverSnapshot: snapshot,
      rateSnapshot: rateSnapshot(quote), quote, exactBaseFareCents: quote.riderBaseFareCents,
      currency: "usd", expiresAt: request.selectionClosesAt, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()
    });
    if (isQuick && lock) {
      const lockRef = requestRef.collection("priceLocks").doc("v1");
      writeLocks(tx, lock.refs, request, uid, lock.window.startsAtMs, lock.window.endsAtMs);
      tx.create(lockRef, priceLockData(requestId, String(request.riderId), uid, uid, request, quote));
      tx.update(requestRef, {
        status: "confirmed", assignedDriverId: uid, selectedOfferId: uid, priceLockId: "v1",
        activeOfferCount: 1, offerDriverIds: [uid], confirmedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()
      });
      tx.update(opportunities().doc(requestId), { status: "assigned", assignedDriverId: uid, updatedAt: FieldValue.serverTimestamp() });
      return { requestId, offerId: uid, status: "confirmed", assigned: true };
    }
    tx.update(requestRef, {
      status: "awaitingRiderSelection", activeOfferCount: count + 1,
      offerDriverIds: FieldValue.arrayUnion(uid), updatedAt: FieldValue.serverTimestamp()
    });
    if (count + 1 >= config.maximumOffers) tx.update(opportunities().doc(requestId), { status: "offerLimitReached", updatedAt: FieldValue.serverTimestamp() });
    return { requestId, offerId: uid, status: "active", assigned: false };
  });
}

export async function selectScheduledRideOfferForUser(uid: string, raw: unknown): Promise<Data> {
  const config = await loadConfig(uid, "rider");
  const input = object(raw, "selection");
  assertOnlyKeys(input, ["requestId", "offerId"]);
  const requestId = string(input.requestId, "requestId", 100);
  const offerId = string(input.offerId, "offerId", 128);
  const requestRef = requests().doc(requestId);
  const offerRef = requestRef.collection("offers").doc(offerId);
  const driverRef = db.collection("drivers").doc(offerId);
  const statusRef = db.collection("driver_status").doc(offerId);
  const profileRef = db.collection("publicDriverProfiles").doc(offerId);

  return db.runTransaction(async (tx) => {
    const [requestSnap, offerSnap, driverSnap, statusSnap, profileSnap] = await Promise.all([
      tx.get(requestRef), tx.get(offerRef), tx.get(driverRef), tx.get(statusRef), tx.get(profileRef)
    ]);
    if (!requestSnap.exists || !offerSnap.exists) throw new HttpsError("not-found", "Request or offer was not found.");
    const request = requestSnap.data() as Data;
    const offer = offerSnap.data() as Data;
    if (request.riderId !== uid) throw new HttpsError("permission-denied", "Only the rider may select an offer.");
    if (request.selectionMode !== "chooseDriver" || !["seekingDrivers", "awaitingRiderSelection"].includes(String(request.status))) {
      throw new HttpsError("failed-precondition", "Request is not awaiting rider selection.");
    }
    if (offer.status !== "active" || (request.selectionClosesAt as admin.firestore.Timestamp).toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "Offer is no longer selectable.");
    }
    const driver = (driverSnap.data() ?? {}) as Data;
    const rideType = canonicalRideType(String(request.rideType));
    if (
      !rideType || !driverIsApproved(driver) || !driverSupports(driver, rideType) ||
      !driverMeetsPreferences(driver, (profileSnap.data() ?? {}) as Data, request.preferences as Data)
    ) {
      throw new HttpsError("failed-precondition", "Selected driver is no longer eligible.");
    }
    if (statusSnap.exists && statusSnap.get("hasActiveRide") === true) {
      throw new HttpsError("failed-precondition", "Selected driver currently has an active ride.");
    }
    const lock = await readLockSnapshots(tx, offerId, request, config);
    const quote = offer.quote as ScheduledRideQuote;
    const lockRef = requestRef.collection("priceLocks").doc("v1");
    writeLocks(tx, lock.refs, request, offerId, lock.window.startsAtMs, lock.window.endsAtMs);
    tx.create(lockRef, priceLockData(requestId, uid, offerId, offerId, request, quote));
    tx.update(offerRef, { status: "selected", selectedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    tx.update(requestRef, {
      status: "confirmed", assignedDriverId: offerId, selectedOfferId: offerId, priceLockId: "v1",
      confirmedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()
    });
    tx.update(opportunities().doc(requestId), { status: "assigned", assignedDriverId: offerId, updatedAt: FieldValue.serverTimestamp() });
    return { requestId, offerId, status: "confirmed", lockedBaseFareCents: quote.riderBaseFareCents };
  });
}
