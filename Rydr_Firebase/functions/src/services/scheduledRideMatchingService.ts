// Pricing and driver-matching logic for the Scheduled Rides feature
// (Quick Schedule / Choose My Driver). This is the server-side counterpart
// to `ScheduledRideManager.swift`'s mock progression — it exists so that
// flipping `ScheduledRideManager.useMockData` to `false` produces real
// offers instead of simulated ones, using the exact same pricing tiers and
// driver-matching conventions the on-demand flow already uses
// (`RydrPricing` in RideManager.swift, `FirestoreRideService.driverCandidate`).
//
// Field names below intentionally mirror `ScheduledRide.swift`'s own
// documented contract (riderApprovedMaxCents, lockedPriceCents,
// assignedDriverId, riderSelectedOfferId, offers subcollection) rather than
// introducing a new shape — this *is* "Ashank's contract" the client was
// built ahead of.

import { db } from "../admin";

export interface TierPricing {
  minimumRideSubtotal: number;
  bookingFeeUnderFiveMiles: number;
  bookingFeeFiveMilesOrMore: number;
  minPerMile: number;
  maxPerMile: number;
  minPerMinute: number;
  maxPerMinute: number;
}

// Mirrors RydrPricing.config(for:) in RideManager.swift exactly — dollars,
// not cents, to match the Swift source of truth 1:1 before conversion.
const TIERS: Record<string, TierPricing> = {
  eco: { minimumRideSubtotal: 7.0, bookingFeeUnderFiveMiles: 3.0, bookingFeeFiveMilesOrMore: 5.0, minPerMile: 0.5, maxPerMile: 1.1, minPerMinute: 0.15, maxPerMinute: 0.25 },
  go: { minimumRideSubtotal: 7.0, bookingFeeUnderFiveMiles: 3.0, bookingFeeFiveMilesOrMore: 6.0, minPerMile: 0.5, maxPerMile: 1.0, minPerMinute: 0.15, maxPerMinute: 0.25 },
  xl: { minimumRideSubtotal: 9.0, bookingFeeUnderFiveMiles: 4.0, bookingFeeFiveMilesOrMore: 8.0, minPerMile: 0.5, maxPerMile: 1.25, minPerMinute: 0.15, maxPerMinute: 0.25 },
  prestine: { minimumRideSubtotal: 12.0, bookingFeeUnderFiveMiles: 5.0, bookingFeeFiveMilesOrMore: 10.0, minPerMile: 0.75, maxPerMile: 1.5, minPerMinute: 0.15, maxPerMinute: 0.35 },
  executive: { minimumRideSubtotal: 18.0, bookingFeeUnderFiveMiles: 8.0, bookingFeeFiveMilesOrMore: 15.0, minPerMile: 1.0, maxPerMile: 2.0, minPerMinute: 0.25, maxPerMinute: 0.5 }
};

const DRIVER_PAYOUT_SHARE = 0.7;
export const MAX_OFFERS = 3;
export const OFFER_TTL_SECONDS = 90;
const SEARCH_RADIUS_MILES = 30;

/** Mirrors FirestoreRideService.canonicalRideType(_:) exactly. */
export function canonicalRideType(rideType: string): string {
  const key = (rideType || "").trim().toLowerCase();
  if (key === "rydr" || key === "rydr go") return "go";
  if (key === "rydr eco") return "eco";
  if (key === "rydr xl") return "xl";
  if (key === "rydr prestine" || key === "rydr pristine") return "prestine";
  if (key === "rydr executive") return "executive";
  return key;
}

function tierFor(rideType: string): TierPricing {
  return TIERS[canonicalRideType(rideType)] ?? TIERS.go;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function bookingFee(pricing: TierPricing, distanceMiles: number): number {
  return distanceMiles < 5 ? pricing.bookingFeeUnderFiveMiles : pricing.bookingFeeFiveMilesOrMore;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/** Mirrors RideManager.fareBreakdown(estimate:with:rideType:).finalRiderTotal
 * exactly (same operation order), returning the final rider total in cents. */
export function lockedPriceCents(
  rideType: string,
  distanceMiles: number,
  durationMinutes: number,
  driverPerMile: number,
  driverPerMinute: number
): number {
  const pricing = tierFor(rideType);
  const perMile = clamp(driverPerMile, pricing.minPerMile, pricing.maxPerMile);
  const perMinute = clamp(driverPerMinute, pricing.minPerMinute, pricing.maxPerMinute);
  const distanceCost = distanceMiles * perMile;
  const timeCost = durationMinutes * perMinute;
  const calculatedSubtotal = distanceCost + timeCost;
  const minimumFareAdjustment = Math.max(0, pricing.minimumRideSubtotal - calculatedSubtotal);
  const rideSubtotal = calculatedSubtotal + minimumFareAdjustment;
  const finalRiderTotal = rideSubtotal + bookingFee(pricing, distanceMiles);
  return Math.round(round2(finalRiderTotal) * 100);
}

/** Approved-maximum range shown before a request is created — the low end
 * uses the tier's minimum driver rate, the high end its maximum. Mirrors
 * `ScheduledRideManager.priceRange(estimate:rideType:)`'s own math so the
 * number the rider approves and the number the backend can actually lock
 * against are computed the same way. */
export function approvedMaxRangeCents(rideType: string, distanceMiles: number, durationMinutes: number): { lowCents: number; highCents: number } {
  const pricing = tierFor(rideType);
  return {
    lowCents: lockedPriceCents(rideType, distanceMiles, durationMinutes, pricing.minPerMile, pricing.minPerMinute),
    highCents: lockedPriceCents(rideType, distanceMiles, durationMinutes, pricing.maxPerMile, pricing.maxPerMinute)
  };
}

function haversineMiles(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 3958.8;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

/** Mirrors FirestoreRideService's coordinate(from:) fallback chain
 * (geoPoint / approximateLocation / location / lat+lng). */
function driverCoordinate(data: FirebaseFirestore.DocumentData): { lat: number; lng: number } | null {
  const geoPoint = data.geoPoint as FirebaseFirestore.GeoPoint | undefined;
  if (geoPoint && typeof geoPoint.latitude === "number") {
    return { lat: geoPoint.latitude, lng: geoPoint.longitude };
  }
  for (const key of ["approximateLocation", "location"]) {
    const nested = data[key] as Record<string, unknown> | undefined;
    const lat = numberValue(nested?.lat);
    const lng = numberValue(nested?.lng);
    if (lat !== undefined && lng !== undefined) return { lat, lng };
  }
  const lat = numberValue(data.lat);
  const lng = numberValue(data.lng);
  if (lat !== undefined && lng !== undefined) return { lat, lng };
  return null;
}

/** Mirrors FirestoreRideService's driverRate(from:rideType:pricing:). */
function driverRate(data: FirebaseFirestore.DocumentData, rideType: string, pricing: TierPricing): { perMile: number; perMinute: number } {
  const tierRates = data.tierRates as Record<string, Record<string, unknown>> | undefined;
  const canonical = canonicalRideType(rideType);
  const rawRate = tierRates?.[canonical];
  const rawPerMile = numberValue(rawRate?.perMile) ?? numberValue(data.perMile) ?? pricing.minPerMile;
  const rawPerMinute = numberValue(rawRate?.perMinute) ?? numberValue(data.perMinute) ?? pricing.minPerMinute;
  return {
    perMile: clamp(rawPerMile, pricing.minPerMile, pricing.maxPerMile),
    perMinute: clamp(rawPerMinute, pricing.minPerMinute, pricing.maxPerMinute)
  };
}

function driverDisplayName(data: FirebaseFirestore.DocumentData): string {
  const firstNameOnly = (name: string) => {
    const trimmed = name.trim();
    if (!trimmed) return "Rydr Driver";
    return trimmed.split(/\s+/)[0];
  };
  const displayName = data.displayName as string | undefined;
  if (displayName && displayName.trim()) return firstNameOnly(displayName);
  const first = (data.firstName as string | undefined)?.trim();
  if (first) return firstNameOnly(first);
  const name = (data.name as string | undefined)?.trim();
  return name ? firstNameOnly(name) : "Rydr Driver";
}

function vehicleName(data: FirebaseFirestore.DocumentData): string {
  const summary = data.vehicleSummary as string | undefined;
  if (summary && summary.trim()) return summary.trim();
  const makeModel = data.carMakeModel as string | undefined;
  return makeModel && makeModel.trim() ? makeModel.trim() : "Verified Rydr vehicle";
}

export interface MatchedDriver {
  driverId: string;
  driverName: string;
  driverProfileImage: string | null;
  carImage: string | null;
  carMakeModel: string;
  rating: number;
  ratingCount: number;
  perMile: number;
  perMinute: number;
  lockedPriceCents: number;
  distanceMiles: number;
}

/** Finds up to MAX_OFFERS eligible online drivers for a ride, mirroring the
 * eligibility rules FirestoreRideService.fetchNearbyDrivers already applies
 * for on-demand rides (online, ride-type eligible, not temporarily
 * disabled, within 30mi), sorted nearest-first. `excludeDriverIds` lets a
 * re-match (after a driver cancellation) skip drivers already tried. */
export async function matchDrivers(params: {
  rideType: string;
  pickupLat: number;
  pickupLng: number;
  distanceMiles: number;
  durationMinutes: number;
  excludeDriverIds?: string[];
}): Promise<MatchedDriver[]> {
  const { rideType, pickupLat, pickupLng, distanceMiles, durationMinutes } = params;
  const exclude = new Set(params.excludeDriverIds ?? []);
  const pricing = tierFor(rideType);
  const canonical = canonicalRideType(rideType);

  if (canonical === "executive") {
    const gate = await db.collection("platformConfig").doc("rydrExecutive").get();
    if (gate.data()?.enabled !== true) return [];
  }

  const snapshot = await db.collection("publicDriverProfiles").where("isOnline", "==", true).get();

  const candidates: (MatchedDriver & { _sortDistance: number; _rating: number })[] = [];
  snapshot.forEach((doc) => {
    if (exclude.has(doc.id)) return;
    const data = doc.data();
    if (data.standardDispatchEnabled === false) return;
    const disabledRideTypes = (data.temporarilyDisabledRideTypes as string[] | undefined) ?? [];
    if (disabledRideTypes.some((t) => canonicalRideType(t) === canonical)) return;

    const eligible = (data.eligibleRideTypes ?? data.selectedRideTypes ?? data.rideTypes ?? data.supportedRideTypes) as string[] | undefined;
    if (eligible && eligible.length > 0 && !eligible.some((t) => canonicalRideType(t) === canonical)) return;

    const coordinate = driverCoordinate(data);
    if (!coordinate) return;
    const distance = haversineMiles(pickupLat, pickupLng, coordinate.lat, coordinate.lng);
    if (distance > SEARCH_RADIUS_MILES) return;

    const rating = numberValue(data.rating) ?? 5.0;
    const rate = driverRate(data, rideType, pricing);

    candidates.push({
      driverId: doc.id,
      driverName: driverDisplayName(data),
      driverProfileImage: (data.profilePhotoURL as string) || (data.profileImage as string) || null,
      carImage: (data.vehicleImageURL as string) || (data.carImage as string) || null,
      carMakeModel: vehicleName(data),
      rating,
      ratingCount: numberValue(data.ratingCount) ?? 0,
      perMile: rate.perMile,
      perMinute: rate.perMinute,
      lockedPriceCents: lockedPriceCents(rideType, distanceMiles, durationMinutes, rate.perMile, rate.perMinute),
      distanceMiles: Math.round(distance * 10) / 10,
      _sortDistance: Math.round(distance * 10) / 10,
      _rating: rating
    });
  });

  candidates.sort((a, b) => a._sortDistance - b._sortDistance || b._rating - a._rating);
  return candidates.slice(0, MAX_OFFERS).map(({ _sortDistance, _rating, ...rest }) => rest);
}
