"use strict";

const CASH_HUB_MONTHLY_FEE_CENTS = 499;
const CASH_HUB_GRACE_DAYS = 5;
const CASH_HUB_TIME_ZONE = "America/New_York";

function businessDateParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: CASH_HUB_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(date);
  const value = (type) => Number(parts.find((part) => part.type === type)?.value);
  return { year: value("year"), month: value("month"), day: value("day") };
}

function billingPeriod(date = new Date()) {
  const { year, month } = businessDateParts(date);
  return `${year}-${String(month).padStart(2, "0")}`;
}

function graceEndDate(date = new Date()) {
  const { year, month } = businessDateParts(date);
  // Noon UTC avoids DST-boundary ambiguity. Access enforcement is performed by
  // the daily America/New_York scheduler, not by comparing this display value.
  return new Date(Date.UTC(year, month - 1, CASH_HUB_GRACE_DAYS + 1, 12));
}

function billingStatus({ collectedCents, remainingCents, reservedCents = 0, pastDue = false }) {
  if (remainingCents <= 0) return "collected";
  if (pastDue) return "past_due";
  if (collectedCents > 0 || reservedCents > 0) return "partially_collected";
  return "fee_pending";
}

function reservationAmount({ driverPayoutCents, remainingCents, reservedCents = 0 }) {
  const payout = Math.max(0, Math.round(Number(driverPayoutCents) || 0));
  const available = Math.max(0, Math.round(Number(remainingCents) || 0) - Math.max(0, Math.round(Number(reservedCents) || 0)));
  return Math.min(payout, available);
}

function applyCashHubWithholding({ grossDriverPayoutCents, chargeAmountCents, baseApplicationFeeCents, reservedCents }) {
  const gross = Math.max(0, Math.round(Number(grossDriverPayoutCents) || 0));
  const charge = Math.max(0, Math.round(Number(chargeAmountCents) || 0));
  const baseFee = Math.max(0, Math.min(charge, Math.round(Number(baseApplicationFeeCents) || 0)));
  const withheldCents = Math.min(gross, Math.max(0, Math.round(Number(reservedCents) || 0)));
  return {
    cashHubFeeWithheldCents: withheldCents,
    netDriverTransferCents: Math.max(0, gross - withheldCents),
    applicationFeeCents: Math.min(charge, baseFee + withheldCents)
  };
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  return null;
}

function accessWasActivatedForPeriod(driver, date = new Date()) {
  if (!driver || driver.cashHubTermsAccepted !== true || driver.cashHubOptedOut === true) return false;
  const status = String(driver.cashHubAccessStatus || "active").toLowerCase();
  if (["revoked", "optedout", "opted_out"].includes(status)) return false;
  const acceptedAt = timestampMillis(driver.cashHubTermsAcceptedAt);
  if (!acceptedAt) return true;
  const acceptedPeriod = billingPeriod(new Date(acceptedAt));
  return acceptedPeriod <= billingPeriod(date);
}

async function reserveCashHubFee({ admin, driverId, rideId, driverPayoutCents, now = new Date() }) {
  if (!driverId || !rideId || driverPayoutCents <= 0) return { amountCents: 0, periodId: billingPeriod(now), status: "not_eligible" };
  const db = admin.firestore();
  const driverRef = db.collection("drivers").doc(driverId);
  const configSnap = await db.collection("platformConfig").doc("cashRydrHub").get();
  const config = configSnap.exists ? configSnap.data() : {};
  const launchAtMillis = timestampMillis(config.cashHubBillingLaunchAt);
  if (config.termsAcceptanceEnabled !== true || config.cashHubBillingEnabled !== true || (launchAtMillis && now.getTime() < launchAtMillis)) {
    return { amountCents: 0, periodId: billingPeriod(now), status: "billing_disabled" };
  }
  const configuredFeeCents = Math.max(0, Math.round(Number(config.cashHubMonthlyFeeCents) || CASH_HUB_MONTHLY_FEE_CENTS));
  const currentTermsVersion = String(config.cashHubTermsVersion || "legacy");
  const billingDocs = await driverRef.collection("cashHubBilling").limit(24).get();
  const oldestOutstanding = billingDocs.docs
    .filter((doc) => {
      const data = doc.data();
      return (Number(data.remainingCents) || 0) > 0 && ["fee_pending", "partially_collected", "past_due"].includes(String(data.status || ""));
    })
    .sort((left, right) => left.id.localeCompare(right.id))[0];
  const periodId = oldestOutstanding?.id || billingPeriod(now);
  const billingRef = driverRef.collection("cashHubBilling").doc(periodId);
  const reservationRef = billingRef.collection("rideReservations").doc(rideId);

  return db.runTransaction(async (tx) => {
    const [driverSnap, billingSnap, reservationSnap] = await Promise.all([
      tx.get(driverRef), tx.get(billingRef), tx.get(reservationRef)
    ]);
    const driver = driverSnap.exists ? driverSnap.data() : null;
    const existingBilling = billingSnap.exists ? billingSnap.data() : null;
    const incurredObligation = existingBilling
      && (Number(existingBilling.remainingCents) || 0) > 0
      && ["fee_pending", "partially_collected", "past_due"].includes(String(existingBilling.status || ""));
    // Opting out stops future access and future monthly fees. It does not erase
    // a fee already incurred for a month in which access was activated.
    if (!incurredObligation && !accessWasActivatedForPeriod(driver, now)) return { amountCents: 0, periodId, status: "not_eligible" };
    const acceptedTermsVersion = String(driver?.cashHubTermsVersion || "");
    if (!incurredObligation && !(acceptedTermsVersion === currentTermsVersion || (!acceptedTermsVersion && currentTermsVersion === "legacy"))) {
      return { amountCents: 0, periodId, status: "stale_terms" };
    }
    if (reservationSnap.exists && ["reserved", "collected"].includes(reservationSnap.data().status)) {
      const existing = reservationSnap.data();
      return { amountCents: Number(existing.amountCents) || 0, periodId, status: existing.status || "reserved" };
    }

    const billing = existingBilling || {};
    const feeCents = Number(billing.feeCents) || configuredFeeCents;
    const collectedCents = Math.max(0, Number(billing.collectedCents) || 0);
    const remainingCents = Math.max(0, Number(billing.remainingCents) || feeCents - collectedCents);
    const reservedCents = Math.max(0, Number(billing.reservedCents) || 0);
    const amountCents = reservationAmount({ driverPayoutCents, remainingCents, reservedCents });
    if (amountCents <= 0) return { amountCents: 0, periodId, status: remainingCents <= 0 ? "collected" : "not_available" };

    const nextReserved = reservedCents + amountCents;
    tx.set(billingRef, {
      periodId,
      feeCents,
      collectedCents,
      remainingCents,
      reservedCents: nextReserved,
      status: billingStatus({ collectedCents, remainingCents, reservedCents: nextReserved, pastDue: billing.status === "past_due" }),
      graceEndsAt: billing.graceEndsAt || admin.firestore.Timestamp.fromDate(
        launchAtMillis && billingPeriod(new Date(launchAtMillis)) === periodId
          ? new Date(launchAtMillis + CASH_HUB_GRACE_DAYS * 24 * 60 * 60 * 1000)
          : graceEndDate(now)
      ),
      collectionSource: "dispatch_earnings",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: billing.createdAt || admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    tx.set(reservationRef, {
      rideId, driverId, periodId, amountCents, status: "reserved",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    return { amountCents, periodId, status: "reserved" };
  });
}

async function finalizeCashHubFee({ admin, driverId, rideId, periodId, paymentIntentId = null }) {
  if (!driverId || !rideId || !periodId) return { amountCents: 0, status: "not_reserved" };
  const db = admin.firestore();
  const driverRef = db.collection("drivers").doc(driverId);
  const billingRef = driverRef.collection("cashHubBilling").doc(periodId);
  const reservationRef = billingRef.collection("rideReservations").doc(rideId);
  return db.runTransaction(async (tx) => {
    const [billingSnap, reservationSnap, driverSnap] = await Promise.all([tx.get(billingRef), tx.get(reservationRef), tx.get(driverRef)]);
    if (!billingSnap.exists || !reservationSnap.exists) return { amountCents: 0, status: "not_reserved" };
    const reservation = reservationSnap.data();
    const amountCents = Math.max(0, Number(reservation.amountCents) || 0);
    if (reservation.status === "collected") return { amountCents, status: "collected" };
    const billing = billingSnap.data();
    const feeCents = Number(billing.feeCents) || CASH_HUB_MONTHLY_FEE_CENTS;
    const collectedCents = Math.min(feeCents, Math.max(0, Number(billing.collectedCents) || 0) + amountCents);
    const remainingCents = Math.max(0, feeCents - collectedCents);
    const reservedCents = Math.max(0, (Number(billing.reservedCents) || 0) - amountCents);
    const status = billingStatus({ collectedCents, remainingCents, reservedCents });
    tx.set(billingRef, {
      collectedCents, remainingCents, reservedCents, status,
      lastCollectionRideId: rideId,
      lastPaymentIntentId: paymentIntentId,
      lastCollectedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    tx.set(reservationRef, { status: "collected", paymentIntentId, collectedAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    const driver = driverSnap.exists ? driverSnap.data() : {};
    if (remainingCents === 0 && driver.cashHubTermsAccepted === true && driver.cashHubOptedOut !== true) {
      tx.set(driverRef, { cashHubAccessStatus: "active", cashHubAccessRestoredAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }
    return { amountCents, status, remainingCents };
  });
}

async function releaseCashHubFee({ admin, driverId, rideId, periodId, reason = "payment_not_completed" }) {
  if (!driverId || !rideId || !periodId) return;
  const db = admin.firestore();
  const billingRef = db.collection("drivers").doc(driverId).collection("cashHubBilling").doc(periodId);
  const reservationRef = billingRef.collection("rideReservations").doc(rideId);
  await db.runTransaction(async (tx) => {
    const [billingSnap, reservationSnap] = await Promise.all([tx.get(billingRef), tx.get(reservationRef)]);
    if (!billingSnap.exists || !reservationSnap.exists || reservationSnap.data().status !== "reserved") return;
    const amountCents = Math.max(0, Number(reservationSnap.data().amountCents) || 0);
    const billing = billingSnap.data();
    const reservedCents = Math.max(0, (Number(billing.reservedCents) || 0) - amountCents);
    tx.set(billingRef, {
      reservedCents,
      status: billingStatus({ collectedCents: Number(billing.collectedCents) || 0, remainingCents: Number(billing.remainingCents) || CASH_HUB_MONTHLY_FEE_CENTS, reservedCents, pastDue: billing.status === "past_due" }),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    tx.set(reservationRef, { status: "released", releaseReason: String(reason).slice(0, 200), releasedAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  });
}

module.exports = {
  CASH_HUB_MONTHLY_FEE_CENTS,
  CASH_HUB_GRACE_DAYS,
  CASH_HUB_TIME_ZONE,
  businessDateParts,
  billingPeriod,
  graceEndDate,
  billingStatus,
  reservationAmount,
  applyCashHubWithholding,
  accessWasActivatedForPeriod,
  reserveCashHubFee,
  finalizeCashHubFee,
  releaseCashHubFee
};
