const PRICING_VERSION = "standard_usd_v1";
const DRIVER_SHARE_BPS = 7000;

const TIERS = {
  eco: { minimum: 700, under5: 300, over5: 500, mile: [50, 110], minute: [15, 25] },
  go: { minimum: 700, under5: 300, over5: 600, mile: [50, 100], minute: [15, 25] },
  xl: { minimum: 900, under5: 400, over5: 800, mile: [50, 125], minute: [15, 25] },
  prestine: { minimum: 1200, under5: 500, over5: 1000, mile: [75, 150], minute: [15, 35] },
  executive: { minimum: 1800, under5: 800, over5: 1500, mile: [100, 200], minute: [25, 50] }
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

function clamp(value, [minimum, maximum]) {
  return Math.min(maximum, Math.max(minimum, integer(value, minimum)));
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

function calculateOutcome(ride, options = {}) {
  const nowMillis = options.nowMillis || Date.now();
  const tier = tierFor(ride.rideType);
  const config = TIERS[tier];
  const distanceMiles = number(ride.backendDistanceMiles ?? ride.estimatedDistanceMiles ?? ride.distanceMiles);
  const estimatedMinutes = number(ride.backendDurationMinutes ?? ride.estimatedDurationMinutes ?? ride.durationMinutes);
  const startedAt = timestampMillis(ride.rideStartedAt ?? ride.startedAt);
  const endedAt = timestampMillis(ride.completedAt ?? ride.cancelledAt) || nowMillis;
  const actualMinutes = startedAt && endedAt > startedAt ? (endedAt - startedAt) / 60000 : estimatedMinutes;
  const perMileCents = clamp(ride.driverRatePerMileCents, config.mile);
  const perMinuteCents = clamp(ride.driverRatePerMinuteCents, config.minute);
  const midRide = Boolean(startedAt) && ["riderCancelled", "driverCancelled", "cancelled"].includes(ride.status);
  const progress = midRide && estimatedMinutes > 0 ? Math.max(0.05, Math.min(0.95, actualMinutes / estimatedMinutes)) : 1;
  const billableDistance = midRide ? Math.max(0.1, distanceMiles * progress) : distanceMiles;
  const billableMinutes = midRide ? Math.max(1, actualMinutes) : actualMinutes;
  const distanceChargeCents = Math.round(billableDistance * perMileCents);
  const timeChargeCents = Math.round(billableMinutes * perMinuteCents);
  const calculatedSubtotalCents = distanceChargeCents + timeChargeCents;
  const rideSubtotalCents = Math.max(config.minimum, calculatedSubtotalCents);
  const minimumFareAdjustmentCents = rideSubtotalCents - calculatedSubtotalCents;
  const waitStart = timestampMillis(ride.pickupPaidWaitStartedAt);
  const waitEnd = startedAt || endedAt;
  const paidWaitSeconds = waitStart && waitEnd > waitStart ? Math.floor((waitEnd - waitStart) / 1000) : 0;
  const waitChargeCents = Math.round((paidWaitSeconds / 60) * perMinuteCents);
  const cancelledBeforeStart = ["riderCancelled", "driverCancelled", "cancelled"].includes(ride.status) && !midRide;
  const riderCancelled = ride.cancelledByRole === "rider" || ride.status === "riderCancelled";
  const arrived = Boolean(timestampMillis(ride.arrivedAtPickupAt));
  const cancellationFeeCents = cancelledBeforeStart && riderCancelled && arrived ? Math.round(rideSubtotalCents * 0.2) : 0;
  const bookingFeeCents = cancelledBeforeStart ? (riderCancelled && arrived ? (distanceMiles < 5 ? config.under5 : config.over5) : 0) : (distanceMiles < 5 ? config.under5 : config.over5);
  const grossChargeCents = cancelledBeforeStart ? bookingFeeCents + cancellationFeeCents : rideSubtotalCents + bookingFeeCents + waitChargeCents;
  const driverEconomicsCents = cancelledBeforeStart ? cancellationFeeCents : rideSubtotalCents + waitChargeCents;
  const driverPayoutCents = Math.round(driverEconomicsCents * DRIVER_SHARE_BPS / 10000);

  return {
    pricingVersion: PRICING_VERSION,
    currency: "usd",
    outcomeType: midRide ? "mid_ride_cancellation" : cancelledBeforeStart ? (riderCancelled ? "rider_cancellation" : "driver_cancellation") : "completed",
    distanceChargeCents,
    timeChargeCents,
    minimumFareAdjustmentCents,
    rideSubtotalCents,
    bookingFeeCents,
    waitChargeCents,
    cancellationFeeCents,
    grossChargeCents,
    promotionDiscountCents: 0,
    finalRiderChargeCents: grossChargeCents,
    driverPayoutCents,
    platformShareCents: grossChargeCents - driverPayoutCents,
    calculationInputs: { tier, distanceMiles, billableDistance, billableMinutes, perMileCents, perMinuteCents, paidWaitSeconds, evidenceSource: ride.backendDistanceMiles != null && ride.backendDurationMinutes != null ? "backend_route" : "legacy_ride_estimate" },
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
    platformShareCents: outcome.grossChargeCents - outcome.driverPayoutCents,
    appliedRydrBankCredit: true,
    promotionSource: "rydr_bank",
    calculationReason: `${outcome.calculationReason}_rydr_bank_credit`
  };
}

module.exports = { calculateOutcome, applyFullRideCredit, tierFor, PRICING_VERSION };
