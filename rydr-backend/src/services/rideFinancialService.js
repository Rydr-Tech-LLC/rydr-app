const PRICING_VERSION = "standard_usd_v2";
const DRIVER_SHARE_BPS = 9000;
const ETA_GRACE_MINUTES = 5;
const DEFAULT_MINIMUM_FARE_CENTS = 700;

// Booking fees remain platform-owned and mileage-based. Driver-controlled
// minimum, mile, and minute rates are intentionally not capped in v2.
const TIERS = {
  eco: { under5: 300, over5: 500, suggestedMile: 110, suggestedMinute: 25 },
  go: { under5: 300, over5: 600, suggestedMile: 100, suggestedMinute: 25 },
  xl: { under5: 400, over5: 800, suggestedMile: 125, suggestedMinute: 25 },
  prestine: { under5: 500, over5: 1000, suggestedMile: 150, suggestedMinute: 35 },
  executive: { under5: 800, over5: 1500, suggestedMile: 200, suggestedMinute: 50 }
};

function tierFor(value) {
  const key = String(value || "").toLowerCase();
  if (key.includes("eco")) return "eco";
  if (key.includes("xl")) return "xl";
  if (key.includes("prestine") || key.includes("pristine")) return "prestine";
  if (key.includes("executive")) return "executive";
  return "go";
}

function number(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function integer(value, fallback = 0) {
  return Math.round(number(value, fallback));
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (Number.isFinite(value._seconds)) return value._seconds * 1000;
  if (Number.isFinite(value.seconds)) return value.seconds * 1000;
  return null;
}

function bookingFee(config, distanceMiles) {
  return distanceMiles < 5 ? config.under5 : config.over5;
}

function calculateOutcome(ride, options = {}) {
  const nowMillis = options.nowMillis || Date.now();
  const tier = tierFor(ride.rideType);
  const config = TIERS[tier];
  const plannedDistanceMiles = number(ride.backendDistanceMiles ?? ride.estimatedDistanceMiles ?? ride.distanceMiles);
  const estimatedMinutes = number(ride.backendDurationMinutes ?? ride.estimatedDurationMinutes ?? ride.durationMinutes);
  const startedAt = timestampMillis(ride.rideStartedAt ?? ride.startedAt);
  const endedAt = timestampMillis(ride.completedAt ?? ride.cancelledAt) || nowMillis;
  const actualMinutes = startedAt && endedAt > startedAt ? (endedAt - startedAt) / 60000 : estimatedMinutes;
  const perMileCents = integer(ride.driverRatePerMileCents, config.suggestedMile);
  const perMinuteCents = integer(ride.driverRatePerMinuteCents, config.suggestedMinute);
  const minimumFareCents = integer(ride.driverMinimumFareCents, DEFAULT_MINIMUM_FARE_CENTS);
  const cancelled = ["riderCancelled", "driverCancelled", "cancelled"].includes(ride.status);
  const midRide = Boolean(startedAt) && cancelled;

  // Mid-ride cancellation uses distance reduced from trip telemetry. Legacy
  // rides without that evidence retain elapsed-time proration.
  const progress = midRide && estimatedMinutes > 0
    ? Math.max(0.05, Math.min(0.95, actualMinutes / estimatedMinutes))
    : 1;
  const actualDistance = ride.backendActualDistanceMiles == null
    ? -1
    : number(ride.backendActualDistanceMiles, -1);
  const billableDistance = midRide
    ? (actualDistance >= 0 ? actualDistance : Math.max(0.1, plannedDistanceMiles * progress))
    : plannedDistanceMiles;

  // Completed rides retain the upfront ETA unless they exceed its five-minute
  // grace period. Only minutes beyond the grace are added.
  const overtimeMinutes = !midRide && actualMinutes > estimatedMinutes + ETA_GRACE_MINUTES
    ? actualMinutes - estimatedMinutes - ETA_GRACE_MINUTES
    : 0;
  const billableMinutes = midRide ? Math.max(1, actualMinutes) : estimatedMinutes + overtimeMinutes;
  const timeAdjustmentMinutes = midRide ? 0 : overtimeMinutes;

  const distanceChargeCents = Math.round(billableDistance * perMileCents);
  const baseTimeChargeCents = Math.round((midRide ? billableMinutes : estimatedMinutes) * perMinuteCents);
  const timeAdjustmentCents = Math.round(timeAdjustmentMinutes * perMinuteCents);
  const timeChargeCents = baseTimeChargeCents + timeAdjustmentCents;
  const calculatedSubtotalCents = distanceChargeCents + timeChargeCents;
  const rideSubtotalCents = Math.max(minimumFareCents, calculatedSubtotalCents);
  const minimumFareAdjustmentCents = rideSubtotalCents - calculatedSubtotalCents;
  const waitStart = timestampMillis(ride.pickupPaidWaitStartedAt);
  const waitEnd = startedAt || endedAt;
  const paidWaitSeconds = waitStart && waitEnd > waitStart ? Math.floor((waitEnd - waitStart) / 1000) : 0;
  const rawWaitChargeCents = Math.round((paidWaitSeconds / 60) * perMinuteCents);
  const cancelledBeforeStart = cancelled && !midRide;
  const riderCancelled = ride.cancelledByRole === "rider" || ride.status === "riderCancelled";
  const waitChargeCents = cancelledBeforeStart && !riderCancelled ? 0 : rawWaitChargeCents;
  const arrived = Boolean(timestampMillis(ride.arrivedAtPickupAt));
  const cancellationFeeCents = cancelledBeforeStart && riderCancelled && arrived
    ? Math.round(rideSubtotalCents * 0.2)
    : 0;
  const feeDistance = midRide ? billableDistance : plannedDistanceMiles;
  const rawBookingFeeCents = cancelledBeforeStart
    ? (riderCancelled && arrived ? bookingFee(config, feeDistance) : 0)
    : bookingFee(config, feeDistance);
  const bookingFeeCreditCents = Math.min(rawBookingFeeCents, integer(ride.bookingFeeCreditCents));
  const bookingFeeCents = rawBookingFeeCents - bookingFeeCreditCents;

  let grossChargeCents;
  let driverPayoutCents;
  let platformShareCents;
  if (cancelledBeforeStart) {
    const waitDriverPayoutCents = Math.round(waitChargeCents * DRIVER_SHARE_BPS / 10000);
    grossChargeCents = bookingFeeCents + cancellationFeeCents + waitChargeCents;
    driverPayoutCents = cancellationFeeCents + waitDriverPayoutCents;
    platformShareCents = grossChargeCents - driverPayoutCents;
  } else {
    const driverEconomicsCents = rideSubtotalCents + waitChargeCents;
    grossChargeCents = driverEconomicsCents + bookingFeeCents;
    driverPayoutCents = Math.round(driverEconomicsCents * DRIVER_SHARE_BPS / 10000);
    platformShareCents = grossChargeCents - driverPayoutCents;
  }

  return {
    pricingVersion: PRICING_VERSION,
    currency: "usd",
    outcomeType: midRide ? "mid_ride_cancellation" : cancelledBeforeStart ? (riderCancelled ? "rider_cancellation" : "driver_cancellation") : "completed",
    distanceChargeCents,
    timeChargeCents,
    timeAdjustmentCents,
    minimumFareCents,
    minimumFareAdjustmentCents,
    rideSubtotalCents,
    bookingFeeBeforeCreditCents: rawBookingFeeCents,
    bookingFeeCreditCents,
    bookingFeeCents,
    waitChargeCents,
    cancellationFeeCents,
    grossChargeCents,
    promotionDiscountCents: 0,
    finalRiderChargeCents: grossChargeCents,
    driverPayoutCents,
    platformShareCents,
    calculationInputs: {
      tier,
      plannedDistanceMiles,
      distanceMiles: plannedDistanceMiles,
      billableDistance,
      estimatedMinutes,
      actualMinutes,
      billableMinutes,
      timeAdjustmentMinutes,
      etaGraceMinutes: ETA_GRACE_MINUTES,
      minimumFareCents,
      perMileCents,
      perMinuteCents,
      paidWaitSeconds,
      evidenceSource: midRide
        ? (actualDistance >= 0 ? "trip_telemetry" : "elapsed_time_proration")
        : (ride.backendDistanceMiles != null && ride.backendDurationMinutes != null ? "backend_route" : "legacy_ride_estimate")
    },
    calculationReason: midRide ? "mid_ride_cancellation" : cancelledBeforeStart ? (arrived ? "post_arrival_cancellation" : "no_fee_cancellation") : "ride_completed",
    status: "finalized",
    calculatedBy: "rydr-backend"
  };
}

function applyFullRideCredit(outcome, hasCredit) {
  if (!hasCredit) return outcome;
  return {
    ...outcome,
    promotionDiscountCents: outcome.grossChargeCents,
    finalRiderChargeCents: 0,
    appliedRydrBankCredit: true,
    promotionSource: "rydr_bank",
    calculationReason: `${outcome.calculationReason}_rydr_bank_credit`
  };
}

module.exports = {
  calculateOutcome,
  applyFullRideCredit,
  tierFor,
  PRICING_VERSION,
  DRIVER_SHARE_BPS,
  ETA_GRACE_MINUTES,
  DEFAULT_MINIMUM_FARE_CENTS,
  TIERS
};
