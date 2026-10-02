const { admin, getFirestore } = require("../config/firebase");
const { DEFAULT_MINIMUM_FARE_CENTS, PRICING_VERSION, TIERS, tierFor } = require("./rideFinancialService");
const { normalizedLocation, normalizedRideTypes } = require("./driverPresenceService");

const DEMAND_RADIUS_MILES = 5;
const MAX_PENDING_SIGNALS = 200;
const DEMAND_ADJUSTMENT_CENTS = {
  low: -10,
  moderate: 10,
  high: 20
};

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

function coordinate(value) {
  if (!value || typeof value !== "object") return null;
  return normalizedLocation({
    lat: value.lat ?? value.latitude,
    lng: value.lng ?? value.longitude
  });
}

function driverCoordinate(driver) {
  return coordinate(driver?.location)
    || coordinate(driver?.driverLocation)
    || coordinate(driver?.approximateLocation)
    || coordinate(driver);
}

function distanceMiles(a, b) {
  const radiusMiles = 3958.7613;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const aLat = (a.lat * Math.PI) / 180;
  const bLat = (b.lat * Math.PI) / 180;
  const haversine = Math.sin(dLat / 2) ** 2
    + Math.cos(aLat) * Math.cos(bLat) * Math.sin(dLng / 2) ** 2;
  return radiusMiles * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
}

function demandLevelForCount(count) {
  if (count >= 3) return "high";
  if (count >= 1) return "moderate";
  return "low";
}

function paceTextForLevel(level) {
  if (level === "high") return "1-3 min since last request";
  if (level === "moderate") return "3-5 min since last request";
  return "5+ min since last request";
}

function suggestedRatesFor(rideType, demandLevel) {
  const tier = tierFor(rideType);
  const config = TIERS[tier];
  const level = Object.hasOwn(DEMAND_ADJUSTMENT_CENTS, demandLevel) ? demandLevel : "low";
  const adjustment = DEMAND_ADJUSTMENT_CENTS[level];
  return {
    rideType: tier,
    demandLevel: level,
    minimumFareCents: DEFAULT_MINIMUM_FARE_CENTS,
    perMileCents: Math.max(0, config.suggestedMile + adjustment),
    perMinuteCents: Math.max(0, config.suggestedMinute + adjustment)
  };
}

function pendingSignalData(signal) {
  return typeof signal?.data === "function" ? signal.data() : signal;
}

function countNearbySignals(signals, center, rideType, nowMillis = Date.now()) {
  if (!center) return 0;
  const requestedTier = tierFor(rideType);
  return signals.reduce((count, rawSignal) => {
    const signal = pendingSignalData(rawSignal) || {};
    if (signal.status !== "pending") return count;
    const expiresAt = timestampMillis(signal.expiresAt);
    if (expiresAt !== null && expiresAt <= nowMillis) return count;
    if (tierFor(signal.rideType) !== requestedTier) return count;
    const pickup = coordinate(signal.pickupCoordinate) || coordinate(signal.pickupGeoPoint);
    if (!pickup || distanceMiles(center, pickup) > DEMAND_RADIUS_MILES) return count;
    return count + 1;
  }, 0);
}

function demandSnapshotForSignals({ signals, center, rideTypes, nowMillis = Date.now() }) {
  const byRideType = {};
  let totalNearbyRequestCount = 0;
  for (const rideType of rideTypes) {
    const tier = tierFor(rideType);
    if (byRideType[tier]) continue;
    const nearbyRequestCount = countNearbySignals(signals, center, tier, nowMillis);
    const level = demandLevelForCount(nearbyRequestCount);
    totalNearbyRequestCount += nearbyRequestCount;
    byRideType[tier] = {
      level,
      paceText: paceTextForLevel(level),
      nearbyRequestCount,
      radiusMiles: DEMAND_RADIUS_MILES,
      suggestedRates: suggestedRatesFor(tier, level)
    };
  }
  const overallLevel = demandLevelForCount(totalNearbyRequestCount);
  return {
    level: overallLevel,
    paceText: paceTextForLevel(overallLevel),
    nearbyRequestCount: totalNearbyRequestCount,
    radiusMiles: DEMAND_RADIUS_MILES,
    byRideType
  };
}

function allowedRideTypes(driver, requestedRideTypes) {
  const qualified = normalizedRideTypes(
    driver?.qualifiedRideTypes
      ?? driver?.supportedRideTypes
      ?? driver?.eligibleRideTypes
      ?? driver?.rideTypes
  );
  const requested = normalizedRideTypes(requestedRideTypes);
  if (requested.length === 0) return qualified;
  if (qualified.length === 0) return requested;
  const qualifiedTiers = new Set(qualified.map(tierFor));
  return requested.filter((rideType) => qualifiedTiers.has(tierFor(rideType)));
}

async function getDriverDemandSnapshot({ uid, rideTypes, db = getFirestore(), nowMillis = Date.now() }) {
  const [driverSnap, statusSnap] = await Promise.all([
    db.collection("drivers").doc(uid).get(),
    db.collection("driver_status").doc(uid).get()
  ]);
  if (!driverSnap.exists) throw error("Driver profile not found", 404);

  const driver = driverSnap.data();
  const status = statusSnap.exists ? statusSnap.data() : {};
  const center = driverCoordinate(status) || driverCoordinate(driver);
  if (!center) throw error("A current driver location is required", 409);

  const effectiveRideTypes = allowedRideTypes(driver, rideTypes);
  if (effectiveRideTypes.length === 0) throw error("At least one qualified ride type is required", 409);

  const signals = await db.collection("rideRequestSignals")
    .where("status", "==", "pending")
    .limit(MAX_PENDING_SIGNALS)
    .get();
  const snapshot = demandSnapshotForSignals({
    signals: signals.docs,
    center,
    rideTypes: effectiveRideTypes,
    nowMillis
  });
  const resolvedSuggestedRates = {};
  for (const [tier, demand] of Object.entries(snapshot.byRideType)) {
    resolvedSuggestedRates[tier] = {
      ...demand.suggestedRates,
      pricingVersion: PRICING_VERSION
    };
  }
  const resolvedAt = admin.firestore.Timestamp.now();
  const projection = {
    resolvedSuggestedRates,
    suggestedPricingResolvedAt: resolvedAt
  };
  const batch = db.batch();
  batch.set(db.collection("drivers").doc(uid), projection, { merge: true });
  batch.set(db.collection("driver_status").doc(uid), projection, { merge: true });
  batch.set(db.collection("publicDriverProfiles").doc(uid), { uid, ...projection }, { merge: true });
  await batch.commit();
  return snapshot;
}

module.exports = {
  DEMAND_RADIUS_MILES,
  DEMAND_ADJUSTMENT_CENTS,
  demandLevelForCount,
  suggestedRatesFor,
  countNearbySignals,
  demandSnapshotForSignals,
  driverCoordinate,
  getDriverDemandSnapshot
};
