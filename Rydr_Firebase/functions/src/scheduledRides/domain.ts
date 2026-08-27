export const SCHEDULED_RIDE_SCHEMA_VERSION = 1;
export const DEFAULT_PRICING_VERSION = "scheduled-rides-v1";

export const SCHEDULED_RIDE_SELECTION_MODES = ["quick", "chooseDriver"] as const;
export type ScheduledRideSelectionMode = (typeof SCHEDULED_RIDE_SELECTION_MODES)[number];

export const SCHEDULED_RIDE_STATUSES = [
  "seekingDrivers",
  "awaitingRiderSelection",
  "confirmed",
  "checkInRequired",
  "checkedIn",
  "activating",
  "active",
  "completed",
  "replacementSearching",
  "replacementApprovalRequired",
  "cancelled",
  "expired"
] as const;
export type ScheduledRideStatus = (typeof SCHEDULED_RIDE_STATUSES)[number];

export type ScheduledRideTierId = "eco" | "go" | "xl" | "prestine" | "executive";

export interface ScheduledRideTierPricing {
  id: ScheduledRideTierId;
  displayName: string;
  minimumRideSubtotalCents: number;
  bookingFeeUnderFiveMilesCents: number;
  bookingFeeFiveMilesOrMoreCents: number;
  minPerMileCents: number;
  maxPerMileCents: number;
  minPerMinuteCents: number;
  maxPerMinuteCents: number;
}

export interface ScheduledRidesConfig {
  enabled: boolean;
  schemaVersion: number;
  pricingVersion: string;
  allowedRideTypes: ScheduledRideTierId[];
  allowedRiderIds: string[];
  allowedDriverIds: string[];
  maximumOffers: number;
  minimumLeadMinutes: number;
  maximumAdvanceDays: number;
  offerWindowMinutes: number;
  riderSelectionWindowMinutes: number;
  driverCheckInLeadMinutes: number;
  driverCheckInGraceMinutes: number;
  activationBufferMinutes: number;
  reservationLeadMinutes: number;
  reservationTurnaroundMinutes: number;
  scheduleLockBucketMinutes: number;
  driverPayoutBasisPoints: number;
  pricingTiers: Record<ScheduledRideTierId, ScheduledRideTierPricing>;
}

export interface ScheduledRouteEstimate {
  distanceMiles: number;
  durationMinutes: number;
  source: string;
  version: string;
}

export interface ScheduledRideQuote {
  pricingVersion: string;
  estimateSource: string;
  estimateVersion: string;
  driverRatePerMileCents: number;
  driverRatePerMinuteCents: number;
  distanceCostCents: number;
  timeCostCents: number;
  calculatedSubtotalCents: number;
  minimumFareAdjustmentCents: number;
  rideSubtotalCents: number;
  bookingFeeCents: number;
  riderBaseFareCents: number;
  driverPayoutCents: number;
  platformShareCents: number;
  currency: "usd";
}

export const DEFAULT_SCHEDULED_RIDE_PRICING: Record<ScheduledRideTierId, ScheduledRideTierPricing> = {
  eco: {
    id: "eco",
    displayName: "Rydr Eco",
    minimumRideSubtotalCents: 700,
    bookingFeeUnderFiveMilesCents: 300,
    bookingFeeFiveMilesOrMoreCents: 500,
    minPerMileCents: 50,
    maxPerMileCents: 110,
    minPerMinuteCents: 15,
    maxPerMinuteCents: 25
  },
  go: {
    id: "go",
    displayName: "Rydr Go",
    minimumRideSubtotalCents: 700,
    bookingFeeUnderFiveMilesCents: 300,
    bookingFeeFiveMilesOrMoreCents: 600,
    minPerMileCents: 50,
    maxPerMileCents: 100,
    minPerMinuteCents: 15,
    maxPerMinuteCents: 25
  },
  xl: {
    id: "xl",
    displayName: "Rydr XL",
    minimumRideSubtotalCents: 900,
    bookingFeeUnderFiveMilesCents: 400,
    bookingFeeFiveMilesOrMoreCents: 800,
    minPerMileCents: 50,
    maxPerMileCents: 125,
    minPerMinuteCents: 15,
    maxPerMinuteCents: 25
  },
  prestine: {
    id: "prestine",
    displayName: "Rydr Prestine",
    minimumRideSubtotalCents: 1200,
    bookingFeeUnderFiveMilesCents: 500,
    bookingFeeFiveMilesOrMoreCents: 1000,
    minPerMileCents: 75,
    maxPerMileCents: 150,
    minPerMinuteCents: 15,
    maxPerMinuteCents: 35
  },
  executive: {
    id: "executive",
    displayName: "Rydr Executive",
    minimumRideSubtotalCents: 1800,
    bookingFeeUnderFiveMilesCents: 800,
    bookingFeeFiveMilesOrMoreCents: 1500,
    minPerMileCents: 100,
    maxPerMileCents: 200,
    minPerMinuteCents: 25,
    maxPerMinuteCents: 50
  }
};

export const DEFAULT_SCHEDULED_RIDES_CONFIG: ScheduledRidesConfig = {
  enabled: false,
  schemaVersion: SCHEDULED_RIDE_SCHEMA_VERSION,
  pricingVersion: DEFAULT_PRICING_VERSION,
  allowedRideTypes: ["eco", "go", "xl", "prestine", "executive"],
  allowedRiderIds: [],
  allowedDriverIds: [],
  maximumOffers: 3,
  minimumLeadMinutes: 120,
  maximumAdvanceDays: 30,
  offerWindowMinutes: 30,
  riderSelectionWindowMinutes: 30,
  driverCheckInLeadMinutes: 60,
  driverCheckInGraceMinutes: 10,
  activationBufferMinutes: 5,
  reservationLeadMinutes: 60,
  reservationTurnaroundMinutes: 15,
  scheduleLockBucketMinutes: 15,
  driverPayoutBasisPoints: 7000,
  pricingTiers: DEFAULT_SCHEDULED_RIDE_PRICING
};

function integer(value: unknown, fallback: number, min: number, max: number): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isInteger(parsed) && parsed >= min && parsed <= max ? parsed : fallback;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0).map((item) => item.trim())
    : [];
}

function pricingTierFromData(
  id: ScheduledRideTierId,
  value: unknown,
  fallback: ScheduledRideTierPricing
): ScheduledRideTierPricing {
  const data = value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  return {
    id,
    displayName: typeof data.displayName === "string" && data.displayName.trim() ? data.displayName.trim() : fallback.displayName,
    minimumRideSubtotalCents: integer(data.minimumRideSubtotalCents, fallback.minimumRideSubtotalCents, 0, 100_000),
    bookingFeeUnderFiveMilesCents: integer(data.bookingFeeUnderFiveMilesCents, fallback.bookingFeeUnderFiveMilesCents, 0, 100_000),
    bookingFeeFiveMilesOrMoreCents: integer(data.bookingFeeFiveMilesOrMoreCents, fallback.bookingFeeFiveMilesOrMoreCents, 0, 100_000),
    minPerMileCents: integer(data.minPerMileCents, fallback.minPerMileCents, 1, 10_000),
    maxPerMileCents: integer(data.maxPerMileCents, fallback.maxPerMileCents, 1, 10_000),
    minPerMinuteCents: integer(data.minPerMinuteCents, fallback.minPerMinuteCents, 1, 10_000),
    maxPerMinuteCents: integer(data.maxPerMinuteCents, fallback.maxPerMinuteCents, 1, 10_000)
  };
}

export function scheduledRidesConfigFromData(value: unknown): ScheduledRidesConfig {
  const data = value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  const pricingData = data.pricingTiers && typeof data.pricingTiers === "object"
    ? (data.pricingTiers as Record<string, unknown>)
    : {};
  const allowedRideTypes = stringArray(data.allowedRideTypes)
    .map((rideType) => canonicalRideType(rideType))
    .filter((rideType): rideType is ScheduledRideTierId => rideType !== null);

  return {
    enabled: data.enabled === true,
    schemaVersion: integer(data.schemaVersion, DEFAULT_SCHEDULED_RIDES_CONFIG.schemaVersion, 1, 100),
    pricingVersion: typeof data.pricingVersion === "string" && data.pricingVersion.trim()
      ? data.pricingVersion.trim()
      : DEFAULT_SCHEDULED_RIDES_CONFIG.pricingVersion,
    allowedRideTypes: allowedRideTypes.length > 0 ? Array.from(new Set(allowedRideTypes)) : DEFAULT_SCHEDULED_RIDES_CONFIG.allowedRideTypes,
    allowedRiderIds: stringArray(data.allowedRiderIds),
    allowedDriverIds: stringArray(data.allowedDriverIds),
    // The approved MVP contract caps Choose My Driver at three offers.
    maximumOffers: integer(data.maximumOffers, DEFAULT_SCHEDULED_RIDES_CONFIG.maximumOffers, 1, 3),
    minimumLeadMinutes: integer(data.minimumLeadMinutes, DEFAULT_SCHEDULED_RIDES_CONFIG.minimumLeadMinutes, 15, 10_080),
    maximumAdvanceDays: integer(data.maximumAdvanceDays, DEFAULT_SCHEDULED_RIDES_CONFIG.maximumAdvanceDays, 1, 365),
    offerWindowMinutes: integer(data.offerWindowMinutes, DEFAULT_SCHEDULED_RIDES_CONFIG.offerWindowMinutes, 1, 10_080),
    riderSelectionWindowMinutes: integer(
      data.riderSelectionWindowMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.riderSelectionWindowMinutes,
      1,
      10_080
    ),
    driverCheckInLeadMinutes: integer(
      data.driverCheckInLeadMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.driverCheckInLeadMinutes,
      5,
      1_440
    ),
    driverCheckInGraceMinutes: integer(
      data.driverCheckInGraceMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.driverCheckInGraceMinutes,
      0,
      120
    ),
    activationBufferMinutes: integer(
      data.activationBufferMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.activationBufferMinutes,
      1,
      30
    ),
    reservationLeadMinutes: integer(
      data.reservationLeadMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.reservationLeadMinutes,
      5,
      1_440
    ),
    reservationTurnaroundMinutes: integer(
      data.reservationTurnaroundMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.reservationTurnaroundMinutes,
      0,
      240
    ),
    scheduleLockBucketMinutes: integer(
      data.scheduleLockBucketMinutes,
      DEFAULT_SCHEDULED_RIDES_CONFIG.scheduleLockBucketMinutes,
      5,
      60
    ),
    driverPayoutBasisPoints: integer(
      data.driverPayoutBasisPoints,
      DEFAULT_SCHEDULED_RIDES_CONFIG.driverPayoutBasisPoints,
      0,
      10_000
    ),
    pricingTiers: {
      eco: pricingTierFromData("eco", pricingData.eco, DEFAULT_SCHEDULED_RIDE_PRICING.eco),
      go: pricingTierFromData("go", pricingData.go, DEFAULT_SCHEDULED_RIDE_PRICING.go),
      xl: pricingTierFromData("xl", pricingData.xl, DEFAULT_SCHEDULED_RIDE_PRICING.xl),
      prestine: pricingTierFromData("prestine", pricingData.prestine, DEFAULT_SCHEDULED_RIDE_PRICING.prestine),
      executive: pricingTierFromData("executive", pricingData.executive, DEFAULT_SCHEDULED_RIDE_PRICING.executive)
    }
  };
}

export function canonicalRideType(value: string): ScheduledRideTierId | null {
  const key = value.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (key === "eco" || key === "rydreco") return "eco";
  if (key === "go" || key === "rydrgo") return "go";
  if (key === "xl" || key === "rydrxl") return "xl";
  if (["prestine", "pristine", "rydrprestine", "rydrpristine"].includes(key)) return "prestine";
  if (key === "executive" || key === "rydrexecutive") return "executive";
  return null;
}

export function isSelectionMode(value: unknown): value is ScheduledRideSelectionMode {
  return typeof value === "string" && (SCHEDULED_RIDE_SELECTION_MODES as readonly string[]).includes(value);
}

export function clampRateCents(value: number, min: number, max: number): number {
  return Math.min(Math.max(Math.round(value), min), max);
}

export function calculateScheduledRideQuote(
  estimate: ScheduledRouteEstimate,
  tier: ScheduledRideTierPricing,
  perMileCents: number,
  perMinuteCents: number,
  pricingVersion: string,
  driverPayoutBasisPoints: number
): ScheduledRideQuote {
  if (!Number.isFinite(estimate.distanceMiles) || estimate.distanceMiles <= 0 || estimate.distanceMiles > 500) {
    throw new Error("distanceMiles must be greater than zero and no more than 500.");
  }
  if (!Number.isFinite(estimate.durationMinutes) || estimate.durationMinutes <= 0 || estimate.durationMinutes > 1_440) {
    throw new Error("durationMinutes must be greater than zero and no more than 1440.");
  }

  const safePerMile = clampRateCents(perMileCents, tier.minPerMileCents, tier.maxPerMileCents);
  const safePerMinute = clampRateCents(perMinuteCents, tier.minPerMinuteCents, tier.maxPerMinuteCents);
  const distanceCostCents = Math.round(estimate.distanceMiles * safePerMile);
  const timeCostCents = Math.round(estimate.durationMinutes * safePerMinute);
  const calculatedSubtotalCents = distanceCostCents + timeCostCents;
  const minimumFareAdjustmentCents = Math.max(0, tier.minimumRideSubtotalCents - calculatedSubtotalCents);
  const rideSubtotalCents = calculatedSubtotalCents + minimumFareAdjustmentCents;
  const bookingFeeCents = estimate.distanceMiles < 5
    ? tier.bookingFeeUnderFiveMilesCents
    : tier.bookingFeeFiveMilesOrMoreCents;
  const riderBaseFareCents = rideSubtotalCents + bookingFeeCents;
  const driverPayoutCents = Math.round((rideSubtotalCents * driverPayoutBasisPoints) / 10_000);

  return {
    pricingVersion,
    estimateSource: estimate.source,
    estimateVersion: estimate.version,
    driverRatePerMileCents: safePerMile,
    driverRatePerMinuteCents: safePerMinute,
    distanceCostCents,
    timeCostCents,
    calculatedSubtotalCents,
    minimumFareAdjustmentCents,
    rideSubtotalCents,
    bookingFeeCents,
    riderBaseFareCents,
    driverPayoutCents,
    platformShareCents: riderBaseFareCents - driverPayoutCents,
    currency: "usd"
  };
}

export function maximumScheduledRideQuote(
  estimate: ScheduledRouteEstimate,
  tier: ScheduledRideTierPricing,
  pricingVersion: string,
  driverPayoutBasisPoints: number
): ScheduledRideQuote {
  return calculateScheduledRideQuote(
    estimate,
    tier,
    tier.maxPerMileCents,
    tier.maxPerMinuteCents,
    pricingVersion,
    driverPayoutBasisPoints
  );
}

export function minimumScheduledRideQuote(
  estimate: ScheduledRouteEstimate,
  tier: ScheduledRideTierPricing,
  pricingVersion: string,
  driverPayoutBasisPoints: number
): ScheduledRideQuote {
  return calculateScheduledRideQuote(
    estimate,
    tier,
    tier.minPerMileCents,
    tier.minPerMinuteCents,
    pricingVersion,
    driverPayoutBasisPoints
  );
}

export interface ScheduleLockWindow {
  startsAtMs: number;
  endsAtMs: number;
  bucketStartsAtMs: number[];
}

export function scheduleLockWindow(
  scheduledAtMs: number,
  estimatedDurationMinutes: number,
  config: Pick<
    ScheduledRidesConfig,
    "reservationLeadMinutes" | "reservationTurnaroundMinutes" | "scheduleLockBucketMinutes"
  >
): ScheduleLockWindow {
  const startsAtMs = scheduledAtMs - config.reservationLeadMinutes * 60_000;
  const endsAtMs = scheduledAtMs + (estimatedDurationMinutes + config.reservationTurnaroundMinutes) * 60_000;
  const bucketMs = config.scheduleLockBucketMinutes * 60_000;
  const firstBucket = Math.floor(startsAtMs / bucketMs) * bucketMs;
  const bucketStartsAtMs: number[] = [];

  for (let bucketStart = firstBucket; bucketStart < endsAtMs; bucketStart += bucketMs) {
    bucketStartsAtMs.push(bucketStart);
    if (bucketStartsAtMs.length > 200) {
      throw new Error("The scheduled ride requires too many schedule-lock buckets.");
    }
  }

  return { startsAtMs, endsAtMs, bucketStartsAtMs };
}

export function scheduleLockBucketId(bucketStartMs: number): string {
  return new Date(bucketStartMs).toISOString().replace(/[-:.]/g, "").replace("Z", "Z");
}
