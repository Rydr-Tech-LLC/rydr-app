"use strict";
const RESOLVED_PAYMENT_STATUSES = new Set(["paid_externally", "written_off", "refunded"]);
function paymentResolution(ride) {
  return RESOLVED_PAYMENT_STATUSES.has(ride?.paymentStatus)
    ? { status: "resolved", resolutionType: ride.paymentStatus } : null;
}

// These handlers mirror decisions already made in Stripe. They do not issue
// refunds, reverse driver transfers, or submit dispute evidence.
async function reconcileFinancialEvent({ stripe, db, fieldValue, mode, type, objectId }) {
  const isRefund = type === "charge.refunded";
  const record = isRefund ? await stripe.charges.retrieve(objectId) : await stripe.disputes.retrieve(objectId);
  let intentId = typeof record.payment_intent === "string" ? record.payment_intent : record.payment_intent?.id;
  if (!intentId && record.charge) {
    const charge = await stripe.charges.retrieve(typeof record.charge === "string" ? record.charge : record.charge.id);
    intentId = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent?.id;
  }
  if (!intentId) return { ignored: true };
  const intent = await stripe.paymentIntents.retrieve(intentId);
  if (Boolean(intent.livemode) !== (mode === "live") || !intent.metadata?.rideId) return { ignored: true };
  const rideRef = db.collection("rides").doc(intent.metadata.rideId);
  const outcomeRef = rideRef.collection("financial").doc("outcome");
  const reviewRef = db.collection("financialReviewCases").doc(`${isRefund ? "refund" : "dispute"}_${record.id}`);
  return db.runTransaction(async tx => {
    const [rideSnap, outcomeSnap, reviewSnap] = await Promise.all([tx.get(rideRef), tx.get(outcomeRef), tx.get(reviewRef)]);
    const ride = rideSnap.data(), outcome = outcomeSnap.data(), review = reviewSnap.data();
    if (!ride || !outcome || (ride.stripeMode || "test") !== mode
        || ride.riderId !== intent.metadata.riderId
        || ![ride.stripePaymentIntentId, outcome.paymentIntentId].includes(intent.id)) return { ignored: true };
    const now = fieldValue.serverTimestamp();
    const amount = isRefund ? record.amount_refunded : record.amount;
    if (!Number.isSafeInteger(amount) || amount < 0) throw new Error("invalid_financial_adjustment_amount");
    const fullyRefunded = isRefund && amount >= intent.amount_received;
    const disputeWon = !isRefund && ["won", "warning_closed"].includes(record.status);
    const adjustment = isRefund
      ? { refundedAmountCents: amount, refundStatus: fullyRefunded ? "refunded" : "partially_refunded" }
      : { stripeDisputeId: record.id, disputeStatus: record.status, disputedAmountCents: amount };
    tx.set(rideRef, { ...adjustment, ...(fullyRefunded ? { paymentStatus: "refunded" } : {}),
      financialReviewRequired: !disputeWon, updatedAt: now }, { merge: true });
    tx.set(outcomeRef, { ...adjustment, updatedAt: now }, { merge: true });
    tx.set(reviewRef, {
      rideId: rideRef.id, riderId: ride.riderId, driverId: ride.driverId || null,
      kind: isRefund ? "refund" : "dispute", stripeObjectId: record.id, paymentIntentId: intent.id,
      amountCents: amount, currency: intent.currency, stripeMode: mode,
      status: disputeWon ? "resolved" : review && review.amountCents === amount && review.stripeStatus === (isRefund ? adjustment.refundStatus : record.status) ? review.status : "open",
      stripeStatus: isRefund ? adjustment.refundStatus : record.status,
      driverTransferReviewRequired: !disputeWon && Number(ride.netDriverTransferCents || ride.driverPayoutCents || 0) > 0,
      reason: isRefund ? "Review driver transfers and promotion accounting after a Stripe refund." : "Review Stripe dispute and driver transfer exposure.",
      ...(reviewSnap.exists ? {} : { createdAt: now }), updatedAt: now
    }, { merge: true });
    return { reconciled: true, kind: isRefund ? "refund" : "dispute" };
  });
}
async function claimRideSettlement({ db, rideRef, settlementRef, plan, fieldValue }) {
  return db.runTransaction(async tx => {
    const [ride, existing] = await Promise.all([tx.get(rideRef), tx.get(settlementRef)]);
    const resolution = paymentResolution(ride.data());
    if (resolution) return { resolution };
    if (ride.data()?.paymentStatus === "succeeded") return { completed: true, paymentIntentId: ride.data().stripePaymentIntentId || null };
    if (!existing.exists) tx.create(settlementRef, plan);
    tx.set(rideRef, { paymentStatus: "processing", updatedAt: fieldValue.serverTimestamp() }, { merge: true });
    return existing.exists ? existing.data() : plan;
  });
}
module.exports = { paymentResolution, reconcileFinancialEvent, claimRideSettlement };
