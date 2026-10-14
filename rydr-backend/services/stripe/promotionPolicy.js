const RIDER_TYPES = new Set(["rider_fare_discount", "rider_milestone_reward"]);
const DRIVER_TYPES = new Set([
  "driver_per_ride_bonus",
  "driver_milestone_reward",
]);
function millis(v) {
  if (typeof v?.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === "string") return Date.parse(v);
  const s = v?._seconds ?? v?.seconds;
  return Number.isFinite(s) ? s * 1000 : NaN;
}
function code(value) {
  return String(value ?? "")
    .trim()
    .toUpperCase();
}
function tier(value) {
  const v = String(value ?? "").toLowerCase();
  return v.includes("prestine") || v.includes("pristine")
    ? "prestine"
    : v.includes("executive")
      ? "executive"
      : v.includes("eco")
        ? "eco"
        : v.includes("xl")
          ? "xl"
          : v === "go" || v.includes("rydr go") || v === "rydr"
            ? "go"
            : v;
}
function localTimeToISO(local, zone = "America/New_York") {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local))
    throw new Error("Enter a valid date and time.");
  const target = Date.parse(local + "Z");
  let instant = target;
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const format = (d) => {
    const p = Object.fromEntries(
      formatter.formatToParts(d).map((x) => [x.type, x.value]),
    );
    return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
  };
  for (let i = 0; i < 3; i++) {
    const actual = format(new Date(instant));
    if (actual === local) return new Date(instant).toISOString();
    instant += target - Date.parse(actual + "Z");
  }
  throw new Error(
    "This local time does not exist because of a daylight-saving change.",
  );
}
function normalizeMechanics(input, status = "draft") {
  const audience = String(input.type ?? "").startsWith("driver_")
    ? "drivers"
    : "riders";
  const applicationMode =
    input.applicationMode === "code" ? "code" : "automatic";
  const promoCode = code(input.promoCode) || null;
  if (
    promoCode &&
    (!/^[A-Z0-9][A-Z0-9_-]{2,31}$/.test(promoCode) ||
      promoCode.startsWith("RB-"))
  )
    throw new Error(
      "Use a unique 3–32 character promo code with letters, numbers, dashes or underscores; RB- is reserved.",
    );
  if (status !== "draft" && applicationMode === "code" && !promoCode)
    throw new Error("A promo code is required before publishing.");
  const audienceRule = ["all", "new", "beta", "specific"].includes(
    input.audienceRule,
  )
    ? input.audienceRule
    : "all";
  const audienceUserIds = Array.isArray(input.audienceUserIds)
    ? [
        ...new Set(
          input.audienceUserIds.map((x) => String(x).trim()).filter(Boolean),
        ),
      ]
    : [];
  if (
    audienceUserIds.length > 200 ||
    audienceUserIds.some((x) => x.includes("/"))
  )
    throw new Error("Use at most 200 valid account IDs.");
  if (
    status !== "draft" &&
    audienceRule === "specific" &&
    !audienceUserIds.length
  )
    throw new Error("Select the accounts eligible for this promotion.");
  const limitKind = input.limitKind === "distance" ? "distance" : "amount";
  const maxDistanceMiles = Number(input.maxDistanceMiles);
  const rewardExpiresAfterDays = Number(input.rewardExpiresAfterDays ?? 30);
  if (
    !Number.isInteger(rewardExpiresAfterDays) ||
    rewardExpiresAfterDays < 1 ||
    rewardExpiresAfterDays > 365
  )
    throw new Error("Reward expiration must be 1–365 days.");
  if (
    limitKind === "distance" &&
    (!Number.isFinite(maxDistanceMiles) ||
      maxDistanceMiles <= 0 ||
      maxDistanceMiles > 200)
  )
    throw new Error(
      "Distance limits must be greater than 0 and at most 200 miles.",
    );
  if (
    audience === "drivers" &&
    input.type === "driver_per_ride_bonus" &&
    limitKind === "distance"
  )
    throw new Error(
      "Per-ride cash bonuses use an amount, not a free-ride distance limit.",
    );
  return {
    schemaVersion: 2,
    applicationMode,
    promoCode,
    audienceRule,
    audienceUserIds,
    limitKind,
    maxDistanceMiles: limitKind === "distance" ? maxDistanceMiles : null,
    rewardExpiresAfterDays,
    payExcessFare: input.payExcessFare !== false,
    includeBookingFee: true,
    fundingSource: "rydr",
    audience,
  };
}
function market(ride) {
  const c = ride.pickupCoordinate ?? ride.pickupLocation ?? ride.pickup;
  const lat = Number(c?.lat ?? c?.latitude),
    lng = Number(c?.lng ?? c?.longitude);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    if (lat >= 33.2 && lat <= 34.5 && lng >= -85.1 && lng <= -83.7)
      return "atlanta";
    if (lat >= 40.4 && lat <= 41.1 && lng >= -74.3 && lng <= -73.4)
      return lng < -74.04 ? "new jersey" : "new york";
  }
  const v = String(ride.market ?? ride.marketCode ?? ride.serviceMarket ?? "")
    .toLowerCase()
    .replace(/[-_]/g, " ");
  return v === "atl" ? "atlanta" : v === "nyc" ? "new york" : v;
}
function rideEligible(p, ride, now = Date.now(), ignoreSchedule = false) {
  if (
    !ignoreSchedule &&
    (!["active", "scheduled"].includes(p.status) ||
      !Number.isFinite(millis(p.startsAt)) ||
      !Number.isFinite(millis(p.endsAt)) ||
      now < millis(p.startsAt) ||
      now >= millis(p.endsAt))
  )
    return false;
  if (
    !ignoreSchedule &&
    p.pauseIntervals?.some(
      (interval) =>
        now >= millis(interval.startsAt) && now < millis(interval.endsAt),
    )
  )
    return false;
  if (p.appliesTo && !["normalRydr", "both"].includes(p.appliesTo))
    return false;
  if (
    p.markets?.length &&
    !p.markets.some(
      (x) => String(x).toLowerCase().replace(/[-_]/g, " ") === market(ride),
    )
  )
    return false;
  if (
    p.rideTypes?.length &&
    !p.rideTypes.some((x) => tier(x) === tier(ride.rideType))
  )
    return false;
  return true;
}
function audienceEligible(p, uid, profile, priorCount, enrolled = false) {
  if (p.applicationMode === "code" && !enrolled) return false;
  if (p.audienceRule === "specific" && !p.audienceUserIds?.includes(uid))
    return false;
  if (
    (p.audienceRule === "beta" || p.betaOnly) &&
    !(
      profile?.betaInviteVerifiedForAutoApproval ||
      profile?.betaWaiverAccepted ||
      profile?.isBeta ||
      profile?.betaAgreementAccepted
    )
  )
    return false;
  return p.audienceRule !== "new" || enrolled || priorCount === 0;
}
function discountCents(p, outcome, ride) {
  const gross = Math.max(
    0,
    Number(outcome.finalRiderChargeCents ?? outcome.grossChargeCents) || 0,
  );
  const booking = Math.max(
    0,
    Number(outcome.bookingFeeCents ?? ride.bookingFeeCents) || 0,
  );
  const base = Math.max(
    0,
    Number(outcome.rideSubtotalCents ?? ride.rideSubtotalCents) || 0,
  );
  const eligible = Math.min(gross, base + booking);
  let discount = 0;
  const kind =
    p.type === "rider_milestone_reward"
      ? p.rewardKind === "free_ride"
        ? "free_ride"
        : "fixed"
      : p.discountKind;
  if (kind === "percent")
    discount = Math.round(
      (eligible * Math.min(100, Math.max(0, Number(p.discountPercent) || 0))) /
        100,
    );
  else if (kind === "fixed")
    discount = Math.min(
      eligible,
      Number(
        p.type === "rider_milestone_reward" ? p.rewardCents : p.discountCents,
      ) || 0,
    );
  else if (kind === "free_ride") {
    if (p.limitKind === "distance") {
      const distanceValue =
        outcome.calculationInputs?.billableDistance ??
        ride.backendDistanceMiles ??
        ride.estimatedDistanceMiles;
      if (distanceValue == null || distanceValue === "") return 0;
      const distance = Number(distanceValue);
      if (!Number.isFinite(distance) || distance < 0) return 0;
      if (distance > p.maxDistanceMiles && p.payExcessFare === false) return 0;
      const fraction =
        distance > 0 ? Math.min(1, p.maxDistanceMiles / distance) : 1;
      discount = Math.min(eligible, Math.round(base * fraction) + booking);
    } else
      discount = Math.min(
        eligible,
        Number(p.maxDiscountCents ?? p.rewardCents) || 0,
      );
  }
  if (p.maxDiscountCents != null && kind !== "free_ride")
    discount = Math.min(discount, p.maxDiscountCents);
  return Math.max(0, Math.min(gross, Math.round(discount)));
}
function financialAfterPromotion(outcome, discount) {
  const original = outcome.promotionDiscountCents ?? 0;
  const total = Math.min(outcome.grossChargeCents, original + discount);
  return {
    ...outcome,
    promotionDiscountCents: total,
    finalRiderChargeCents: outcome.grossChargeCents - total,
    platformPromotionSubsidyCents: total,
    driverPayoutCents: outcome.driverPayoutCents,
    platformShareCents: outcome.platformShareCents,
  };
}
function validateOffer(p) {
  if (!RIDER_TYPES.has(p.type) && !DRIVER_TYPES.has(p.type))
    throw new Error("Choose a supported promotion offer.");
  const positive = (v, label) => {
    if (!Number.isInteger(v) || v < 1)
      throw new Error(`${label} must be a positive whole number.`);
  };
  for (const key of ["maxRedemptions", "perUserLimit"])
    if (p[key] != null)
      positive(
        p[key],
        key === "maxRedemptions"
          ? "Total redemption limit"
          : "Per-account limit",
      );
  if (p.type === "rider_fare_discount") {
    if (!["percent", "fixed", "free_ride"].includes(p.discountKind))
      throw new Error("Choose a supported discount.");
    if (p.discountKind === "percent") {
      positive(p.discountPercent, "Percentage");
      if (p.discountPercent > 100)
        throw new Error("Percentage cannot exceed 100.");
    }
    if (p.discountKind === "fixed")
      positive(p.discountCents, "Discount amount");
  }
  if (p.type === "driver_per_ride_bonus")
    positive(p.bonusCents, "Bonus amount");
  if (p.type.endsWith("milestone_reward")) {
    positive(p.milestoneRideCount, "Qualifying ride count");
    if (p.type.startsWith("driver_") && p.rewardKind !== "cash_bonus")
      throw new Error("Driver milestone promotions reward a cash bonus.");
    if (
      p.type.startsWith("rider_") &&
      !["free_ride", "fixed"].includes(p.rewardKind)
    )
      throw new Error("Choose a free ride or fare credit reward.");
    if (p.rewardKind !== "free_ride") positive(p.rewardCents, "Reward amount");
  }
  if (
    (p.discountKind === "free_ride" || p.rewardKind === "free_ride") &&
    p.limitKind !== "distance"
  )
    positive(p.maxDiscountCents, "Free ride amount limit");
  if (p.maxDiscountCents != null)
    positive(p.maxDiscountCents, "Maximum discount");
  if (p.appliesTo !== "normalRydr")
    throw new Error(
      "These promotions currently apply to regular Rydr rides. Cash Hub keeps its existing billing policy.",
    );
  return p;
}
module.exports = {
  validateOffer,
  RIDER_TYPES,
  DRIVER_TYPES,
  millis,
  code,
  tier,
  localTimeToISO,
  normalizeMechanics,
  rideEligible,
  audienceEligible,
  discountCents,
  financialAfterPromotion,
};
