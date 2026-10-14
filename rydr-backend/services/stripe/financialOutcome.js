const SUPPORTED_STATUSES = new Set(["finalized", "paid"]);

function nonNegativeInteger(value) {
  return Number.isInteger(value) && value >= 0 ? value : null;
}

function normalizeFinancialOutcome(outcome) {
  if (!outcome || typeof outcome !== "object") {
    return { ok: false, error: "financial_outcome_invalid" };
  }
  if (!SUPPORTED_STATUSES.has(outcome.status)) {
    return { ok: false, error: "financial_outcome_not_finalized" };
  }

  const finalRiderChargeCents = nonNegativeInteger(outcome.finalRiderChargeCents);
  const driverPayoutCents = nonNegativeInteger(outcome.driverPayoutCents);
  const platformShareCents = nonNegativeInteger(outcome.platformShareCents);
  const grossChargeCents = nonNegativeInteger(outcome.grossChargeCents) ?? finalRiderChargeCents;
  const promotionDiscountCents = nonNegativeInteger(outcome.promotionDiscountCents) || 0;
  if (finalRiderChargeCents === null || driverPayoutCents === null || platformShareCents === null) {
    return { ok: false, error: "financial_outcome_invalid_amounts" };
  }
  if (grossChargeCents === null || finalRiderChargeCents !== Math.max(0, grossChargeCents - promotionDiscountCents)) {
    return { ok: false, error: "financial_outcome_discount_invalid" };
  }
  if (driverPayoutCents + platformShareCents !== grossChargeCents) {
    return { ok: false, error: "financial_outcome_unbalanced" };
  }
  if (outcome.currency && String(outcome.currency).toLowerCase() !== "usd") {
    return { ok: false, error: "financial_outcome_currency_unsupported" };
  }

  return {
    ok: true,
    value: {
      status: outcome.status,
      outcomeType: outcome.outcomeType || "completed",
      finalRiderChargeCents,
      grossChargeCents,
      promotionDiscountCents,
      driverPayoutCents,
      platformShareCents,
      waitChargeCents: nonNegativeInteger(outcome.waitChargeCents) || 0,
      currency: "usd",
    },
  };
}

function rideWithFinancialOutcome(ride, outcome) {
  const normalized = normalizeFinancialOutcome(outcome);
  if (!normalized.ok) return normalized;
  const value = normalized.value;
  return {
    ok: true,
    value: {
      ...ride,
      backendFinancialOutcome: true,
      financialOutcomeType: value.outcomeType,
      finalRiderChargeCents: value.finalRiderChargeCents,
      grossChargeCents: value.grossChargeCents,
      promoDiscountCents: value.promotionDiscountCents,
      driverPayoutCents: value.driverPayoutCents,
      estimatedDriverPayoutCents: value.driverPayoutCents,
      estimatedPlatformShareCents: value.platformShareCents,
      backendWaitChargeCents: value.waitChargeCents,
    },
  };
}

module.exports = { normalizeFinancialOutcome, rideWithFinancialOutcome };

// Signed asynchronous success must settle the same server-owned discounted fare.
function paidOutcomeForIntent(outcome, ride, intent, reservation) {
  if (!outcome || outcome.status === 'paid') return null;
  if (intent.metadata?.riderId !== ride.riderId || intent.metadata?.driverId !== (ride.driverId || '')) throw new Error('payment_intent_owner_mismatch');
  const discount = reservation?.discountCents ?? ride.backendPromotionDiscountCents ?? 0;
  if (!Number.isInteger(discount) || discount < 0) throw new Error('promotion_discount_invalid');
  const adjusted = require('./promotionPolicy').financialAfterPromotion(outcome, discount);
  if (intent.amount !== adjusted.finalRiderChargeCents || intent.currency !== 'usd') throw new Error('payment_intent_amount_mismatch');
  return {...adjusted,status:'paid',paymentIntentId:intent.id,appliedPromotionId:reservation?.promotionId ?? ride.appliedPromotionId ?? null};
}
module.exports.paidOutcomeForIntent = paidOutcomeForIntent;
