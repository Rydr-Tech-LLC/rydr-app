const { admin, getFirestore } = require("../config/firebase");
const { calculateOutcome, applyFullRideCredit } = require("./rideFinancialService");
const { calculateAndStoreRideRouteEstimate } = require("./rideRouteService");

const ACTIONS = {
  driver_accept: { from: ["pending"], status: "accepted", fields: ["acceptedAt"], message: "Your driver is on the way." },
  driver_decline: { from: ["pending"], status: "declined", fields: ["declinedAt"], message: "Ride declined.", requestOnly: true },
  driver_miss: { from: ["pending"], status: "missed", fields: ["missedAt"], message: "Ride request expired.", requestOnly: true },
  promote_queue: { from: ["accepted"], status: "accepted", fields: ["activeAt", "queuedRideStartedAt"], message: "Your driver is on the way." },
  start_navigation: { from: ["accepted"], status: "enRouteToPickup", fields: ["navigationStartedAt", "enRouteToPickupAt"], message: "Your driver is on the way." },
  arrive_pickup: { from: ["accepted", "enRouteToPickup", "navigatingToPickup"], status: "arrivedAtPickup", fields: ["arrivedAtPickupAt", "pickupWaitStartedAt"], message: "Your driver has arrived at pickup." },
  start_paid_wait: { from: ["arrivedAtPickup"], status: "arrivedAtPickup", fields: ["pickupPaidWaitStartedAt"], message: "Paid wait time is active." },
  start_ride: { from: ["arrivedAtPickup"], status: "inProgress", fields: ["rideStartedAt", "startedAt", "navigatingToDropoffAt"], message: "Your ride is headed to drop-off." },
  arrive_stop: { from: ["inProgress", "navigatingToStop"], status: "arrivedAtStop", fields: ["arrivedAtStopAt", "stopWaitStartedAt"], message: "Your driver is waiting at the added stop." },
  leave_stop: { from: ["arrivedAtStop"], status: "inProgress", fields: ["headedToDropoffAt", "navigatingToDropoffAt"], message: "Your ride is headed to drop-off." },
  complete: { from: ["inProgress", "navigatingToDropoff"], status: "completed", fields: ["completedAt"], message: "Your ride is complete.", finalizes: true },
  driver_cancel: { from: ["accepted", "enRouteToPickup", "arrivedAtPickup", "inProgress", "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"], status: "driverCancelled", fields: ["cancelledAt"], message: "Your driver cancelled this ride.", finalizes: true },
  rider_cancel: { from: ["pending", "accepted", "enRouteToPickup", "arrivedAtPickup", "inProgress", "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"], status: "riderCancelled", fields: ["cancelledAt"], message: "Ride cancelled.", finalizes: true }
};

function error(message, statusCode) { const err = new Error(message); err.statusCode = statusCode; return err; }

function serverRateFields(driver, rideType) {
  const rates = driver?.tierRates || {};
  const key = Object.keys(rates).find((candidate) => {
    const a = candidate.toLowerCase(); const b = String(rideType || "").toLowerCase();
    return a === b || (b.includes("eco") && a.includes("eco")) || (b.includes("xl") && a.includes("xl")) || (b.includes("executive") && a.includes("executive")) || ((b.includes("prestine") || b.includes("pristine")) && (a.includes("prestine") || a.includes("pristine"))) || (!b.match(/eco|xl|executive|prestine|pristine/) && a.includes("go"));
  });
  const rate = (key && rates[key]) || {};
  const perMile = Number(rate.perMile ?? driver?.perMile);
  const perMinute = Number(rate.perMinute ?? driver?.perMinute);
  return {
    driverRatePerMileCents: Number.isFinite(perMile) ? Math.round(perMile * 100) : undefined,
    driverRatePerMinuteCents: Number.isFinite(perMinute) ? Math.round(perMinute * 100) : undefined
  };
}

function rydrBankRewardGroup(rideType) {
  const key = String(rideType || "").toLowerCase();
  if (key.includes("xl")) return "xl";
  if (key.includes("prestine") || key.includes("pristine")) return "prestine";
  if (key.includes("executive")) return "executive";
  return "go_eco";
}

async function transitionRide({ rideId, action, uid, reason, requestId, queued = false }) {
  const policy = ACTIONS[action];
  if (!policy) throw error("Unsupported ride action", 400);
  if (!requestId || !/^[A-Za-z0-9_-]{8,80}$/.test(requestId)) throw error("requestId is required", 400);
  const db = getFirestore();
  const rideRef = db.collection("rides").doc(rideId);
  const requestRef = db.collection("rideRequests").doc(rideId);
  const signalRef = db.collection("rideRequestSignals").doc(rideId);
  const outcomeRef = rideRef.collection("financial").doc("outcome");

  if (policy.finalizes) {
    try {
      await calculateAndStoreRideRouteEstimate({ rideId, uid });
    } catch (routeError) {
      if (process.env.NODE_ENV !== "test") {
        console.warn("Unable to refresh the backend route before ride finalization", {
          rideId,
          action,
          message: routeError.message
        });
      }
    }
  }

  const result = await db.runTransaction(async (tx) => {
    const [rideSnap, requestSnap, outcomeSnap] = await Promise.all([tx.get(rideRef), tx.get(requestRef), tx.get(outcomeRef)]);
    if (!rideSnap.exists && !requestSnap.exists) throw error("Ride not found", 404);
    const ride = rideSnap.exists ? rideSnap.data() : requestSnap.data();
    const isRiderAction = action === "rider_cancel";
    const assignedDriverId = ride.driverId || ride.targetDriverId || ride.requestedDriverId;
    if ((isRiderAction ? ride.riderId : assignedDriverId) !== uid) throw error("Ride action is not allowed for this user", 403);
    if (ride.lastLifecycleRequestId === requestId) return { status: ride.status, outcome: outcomeSnap.exists ? outcomeSnap.data() : null, duplicate: true };
    if (!policy.from.includes(ride.status)) throw error(`Cannot ${action} from ${ride.status}`, 409);
    if (action === "promote_queue" && ride.driverQueueStatus !== "queued") throw error("Ride is not queued", 409);
    if (!["driver_accept", "promote_queue", "driver_cancel", "rider_cancel"].includes(action) && ride.driverQueueStatus === "queued") {
      throw error("Queued ride must be promoted before navigation starts", 409);
    }

    const driverSnap = ride.driverId ? await tx.get(db.collection("drivers").doc(ride.driverId)) : null;
    let rydrBankCredit = null;
    const rydrBankCode = typeof ride.rydrBankCode === "string" ? ride.rydrBankCode.trim() : "";
    if (action === "complete" && !outcomeSnap.exists && rydrBankCode) {
      if (!/^RB-[A-Z0-9-]{4,32}$/i.test(rydrBankCode)) throw error("RydrBank code is invalid", 409);
      const indexRef = db.collection("codes_index").doc(rydrBankCode);
      const indexSnap = await tx.get(indexRef);
      if (!indexSnap.exists || indexSnap.data().currentOwnerUid !== ride.riderId) throw error("RydrBank code is not owned by this rider", 409);
      const codePath = indexSnap.data().codeDocPath;
      if (typeof codePath !== "string" || !codePath) throw error("RydrBank code record is invalid", 409);
      const codeRef = db.doc(codePath);
      const codeSnap = await tx.get(codeRef);
      const codeData = codeSnap.exists ? codeSnap.data() : null;
      if (!codeData || !["active", "reserved"].includes(codeData.status)) throw error("RydrBank code is no longer available", 409);
      const distanceMiles = Number(ride.backendDistanceMiles ?? ride.estimatedDistanceMiles ?? ride.distanceMiles);
      if (Number.isFinite(distanceMiles) && distanceMiles > Number(codeData.maxMiles || 15)) throw error("Ride exceeds the RydrBank mileage limit", 409);
      if ((codeData.rewardGroup || "go_eco") !== rydrBankRewardGroup(ride.rideType)) throw error("RydrBank code does not match this ride type", 409);
      rydrBankCredit = { code: rydrBankCode, codeRef, ownerUid: ride.riderId };
    }

    const now = admin.firestore.Timestamp.now();
    const hasStop = Boolean(ride.stop || ride.addedStop || ride.stopCoordinate || ride.stopGeoPoint);
    const resolvedStatus = action === "start_ride" && hasStop ? "navigatingToStop" : policy.status;
    const update = { status: resolvedStatus, riderRideState: resolvedStatus, riderStatusMessage: action === "start_ride" && hasStop ? "Your ride is headed to the added stop." : policy.message, updatedAt: now, lastLifecycleRequestId: requestId, lifecycleOwner: "backend" };
    for (const field of policy.fields) update[field] = now;
    if (action === "start_ride" && hasStop) {
      delete update.navigatingToDropoffAt;
      update.navigatingToStopAt = now;
    }
    if (action === "start_paid_wait") update.pickupComplimentaryWaitSeconds = 180;
    if (action === "promote_queue") update.driverQueueStatus = "active";
    if (action.endsWith("cancel")) Object.assign(update, { cancelledBy: uid, cancelledByRole: isRiderAction ? "rider" : "driver", cancellationReason: String(reason || "Other").slice(0, 500) });
    if (action === "driver_accept") Object.assign(update, { acceptedDriverId: uid, driverId: uid, driverQueueStatus: queued ? "queued" : "active", acceptedAt: now, [queued ? "queuedAt" : "activeAt"]: now, riderStatusMessage: queued ? "Your driver is finishing a current ride. You're next in their queue." : policy.message });
    const finalRide = { ...ride, ...serverRateFields(driverSnap?.data(), ride.rideType), ...update };
    let outcome = outcomeSnap.exists ? outcomeSnap.data() : null;
    if (policy.finalizes && !outcome) {
      let calculatedOutcome = calculateOutcome(finalRide, { nowMillis: now.toMillis() });
      if (rydrBankCredit) calculatedOutcome = applyFullRideCredit(calculatedOutcome, true);
      outcome = { rideId, ...calculatedOutcome, calculatedAt: now, createdAt: now, updatedAt: now };
      tx.create(outcomeRef, outcome);
      if (rydrBankCredit) {
        tx.update(rydrBankCredit.codeRef, { status: "used", usedRideId: rideId, reservedRideId: null, usedAt: now });
        tx.set(db.collection("users").doc(rydrBankCredit.ownerUid), {
          rydrBank: { codesAvailable: admin.firestore.FieldValue.increment(-1) },
          updatedAt: now
        }, { merge: true });
      }
      Object.assign(update, {
        pricingVersion: outcome.pricingVersion,
        outcomeType: outcome.outcomeType,
        currency: outcome.currency,
        distanceChargeCents: outcome.distanceChargeCents,
        timeChargeCents: outcome.timeChargeCents,
        minimumFareAdjustmentCents: outcome.minimumFareAdjustmentCents,
        rideSubtotalCents: outcome.rideSubtotalCents,
        bookingFeeCents: outcome.bookingFeeCents,
        waitChargeCents: outcome.waitChargeCents,
        cancellationFeeCents: outcome.cancellationFeeCents,
        grossChargeCents: outcome.grossChargeCents,
        promotionDiscountCents: outcome.promotionDiscountCents,
        appliedRydrBankCredit: outcome.appliedRydrBankCredit === true,
        finalRiderChargeCents: outcome.finalRiderChargeCents,
        driverPayoutCents: outcome.driverPayoutCents,
        platformShareCents: outcome.platformShareCents,
        proratedCancellationChargeCents: outcome.outcomeType === "mid_ride_cancellation" ? outcome.finalRiderChargeCents : null,
        cancellationTotalChargeCents: outcome.outcomeType === "rider_cancellation" ? outcome.finalRiderChargeCents : null,
        financialOutcomeStatus: "finalized",
        paymentStatus: "pending"
      });
    }
    if (!policy.requestOnly) tx.set(rideRef, !rideSnap.exists || action === "driver_accept" ? { ...ride, ...update } : update, { merge: true });
    tx.set(requestRef, update, { merge: true });
    if (action.endsWith("cancel")) tx.set(signalRef, { status: "cancelled", updatedAt: now }, { merge: true });
    return { status: resolvedStatus, outcome, duplicate: false };
  });

  if (action === "driver_accept" && !result.duplicate) {
    try {
      await calculateAndStoreRideRouteEstimate({ rideId, uid });
    } catch (routeError) {
      if (process.env.NODE_ENV !== "test") {
        console.warn("Ride accepted before Apple Maps route estimation completed", {
          rideId,
          message: routeError.message
        });
      }
    }
  }

  return result;
}

module.exports = { transitionRide, ACTIONS };
