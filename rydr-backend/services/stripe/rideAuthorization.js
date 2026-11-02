"use strict";

function failure(code, status = 409, extra = {}) {
  return Object.assign(new Error(code), { code, status, ...extra });
}

// One PaymentIntent owns each authorization generation. Persist its ID before
// confirming so a lost response or authentication challenge never creates a
// second hold. Stripe idempotency also covers a crash before the ID is saved.
class RideAuthorizationService {
  constructor({ stripe, mode, getDb, customerFor, fieldValue }) {
    Object.assign(this, { stripe, mode, getDb, customerFor, fieldValue });
  }
  requestRef(rideId) { return this.getDb().collection("rideRequests").doc(rideId); }
  async patchAwaiting(ref, update) {
    return this.getDb().runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (!snap.exists || !["authorizing", "authorizationFailed"].includes(snap.data().status)) return false;
      tx.set(ref, update, { merge: true });
      return true;
    });
  }
  async authorize(rideId) {
    const ref = this.requestRef(rideId);
    const snap = await ref.get();
    if (!snap.exists) throw failure("ride_request_not_found", 404);
    const ride = snap.data();
    if (!["authorizing", "authorizationFailed"].includes(ride.status)) {
      if (ride.authorizationStatus === "authorized") return { status: "authorized", paymentIntentId: ride.authorizationPaymentIntentId };
      throw failure("ride_not_awaiting_authorization");
    }
    const unpaid = await this.getDb().collection("rides").where("riderId", "==", ride.riderId).where("paymentStatus", "==", "failed").limit(1).get();
    if (!unpaid.empty) throw failure("outstanding_ride_payment", 402);
    const amount = ride.estimatedRiderTotalCents;
    if (!Number.isSafeInteger(amount) || amount < 50) throw failure("invalid_authorization_amount");
    const customerId = await this.customerFor(ride.riderId);
    if (!customerId) throw failure("no_stripe_customer_on_file");
    const customer = await this.stripe.customers.retrieve(customerId);
    let method = ride.requestedPaymentMethodId || customer.invoice_settings?.default_payment_method;
    if (ride.requestedPaymentMethodId) {
      const saved = await this.stripe.paymentMethods.retrieve(ride.requestedPaymentMethodId);
      if (saved.customer !== customerId || saved.type !== "card") throw failure("payment_method_not_owned", 403);
    }
    if (!method) {
      const methods = await this.stripe.paymentMethods.list({ customer: customerId, type: "card", limit: 1 });
      method = methods.data[0]?.id;
    }
    if (!method) throw failure("no_payment_method_on_file");
    const generation = Number(ride.authorizationGeneration || 1);
    let pi = ride.authorizationPaymentIntentId
      ? await this.stripe.paymentIntents.retrieve(ride.authorizationPaymentIntentId)
      : await this.stripe.paymentIntents.create({
        amount, currency: "usd", customer: customerId, payment_method: method,
        payment_method_types: ["card"], capture_method: "manual",
        metadata: { rideId, riderId: ride.riderId, paymentType: "ride_authorization" }
      }, { idempotencyKey: `ride_hold_${rideId}_${generation}` });
    if (pi.status === "canceled") {
      pi = await this.stripe.paymentIntents.create({ amount, currency: "usd", customer: customerId,
        payment_method: method, payment_method_types: ["card"], capture_method: "manual",
        metadata: { rideId, riderId: ride.riderId, paymentType: "ride_authorization" }
      }, { idempotencyKey: `ride_hold_${rideId}_${pi.id}` });
    }
    if (pi.customer !== customerId || pi.amount !== amount || pi.capture_method !== "manual") throw failure("authorization_mismatch");
    await ref.set({ authorizationPaymentIntentId: pi.id, stripeMode: this.mode }, { merge: true });
    try {
      if (["requires_confirmation", "requires_payment_method"].includes(pi.status)) {
        pi = await this.stripe.paymentIntents.confirm(pi.id, { payment_method: method, off_session: true });
      }
    } catch (err) {
      if (!err.payment_intent && !err.raw?.payment_intent) throw err;
      pi = err.payment_intent || err.raw.payment_intent;
    }
    if (pi.status !== "requires_capture") {
      const challenge = pi.status === "requires_action";
      await this.patchAwaiting(ref, { status: "authorizationFailed", authorizationStatus: challenge ? "requires_action" : "failed" });
      throw failure(challenge ? "authentication_required" : "card_authorization_failed", 402,
        { clientSecret: challenge ? pi.client_secret : null, paymentIntentId: pi.id });
    }
    const latest = (await ref.get()).data();
    if (!["authorizing", "authorizationFailed"].includes(latest.status)) {
      const activeStatuses = ["pending", "accepted", "enRouteToPickup", "navigatingToPickup", "arrived", "arrivedAtPickup", "waitingForRider", "inProgress", "navigatingToStop", "arrivedAtStop", "waitingAtStop", "navigatingToDropoff", "completed"];
      if (!activeStatuses.includes(latest.status) || latest.authorizationPaymentIntentId !== pi.id) {
        await this.getDb().collection("authorizationReleaseJobs").doc(`${rideId}_${pi.id}`).set({ rideId, status: "pending", createdAt: this.fieldValue.serverTimestamp() });
        throw failure("ride_request_cancelled");
      }
    }
    const persisted = await this.patchAwaiting(ref, {
      authorizationStatus: "authorized", authorizedAmountCents: pi.amount_capturable,
      authorizationPaymentIntentId: pi.id, authorizationGeneration: generation,
      authorizationCreatedAt: this.fieldValue.serverTimestamp(), stripeMode: this.mode
    });
    if (!persisted) {
      const status = (await ref.get()).data()?.status;
      if (["cancelled", "expired", "riderCancelled", "driverCancelled", "adminCancelled", "noDriversAvailable"].includes(status)) {
        await this.getDb().collection("authorizationReleaseJobs").doc(`${rideId}_${pi.id}`).set({ rideId, status: "pending", createdAt: this.fieldValue.serverTimestamp() });
        throw failure("ride_request_cancelled");
      }
    }
    return { status: "authorized", paymentIntentId: pi.id, amountCents: pi.amount_capturable };
  }
  async release(rideId) {
    const ref = this.requestRef(rideId);
    const snap = await ref.get();
    const data = snap.data() || {};
    const ids = [...new Set([data.authorizationPaymentIntentId, data.settlementPaymentIntentId, data.supersededAuthorizationId].filter(Boolean))];
    let released = false;
    let captured = false;
    for (const id of ids) {
      const pi = await this.stripe.paymentIntents.retrieve(id);
      captured ||= pi.status === "succeeded";
      if (["requires_capture", "requires_action", "requires_confirmation", "requires_payment_method"].includes(pi.status)) {
        await this.stripe.paymentIntents.cancel(id, {}, { idempotencyKey: `release_${id}` });
        released = true;
      }
    }
    if (ids.length) await ref.set({ authorizationStatus: captured ? "captured" : "released" }, { merge: true });
    return { released };
  }

  // Preserve the estimate hold if the final fare needs a larger authorization.
  // A declined increase must not discard funds that were already reserved.
  async settle({ rideId, amount, customerId, paymentMethodId }) {
    const ref = this.requestRef(rideId);
    const snap = await ref.get();
    const data = snap.data() || {};
    let pi = data.settlementPaymentIntentId
      ? await this.stripe.paymentIntents.retrieve(data.settlementPaymentIntentId)
      : data.authorizationPaymentIntentId
        ? await this.stripe.paymentIntents.retrieve(data.authorizationPaymentIntentId) : null;
    if (pi && pi.customer !== customerId) throw failure("authorization_customer_mismatch");
    if (pi?.status === "succeeded") {
      if (pi.amount_received !== amount) throw failure("settled_amount_mismatch");
      return pi;
    }
    if (!pi || pi.status === "canceled" || pi.amount < amount) {
      const previous = pi;
      // The final amount is frozen by the financial outcome/settlement plan.
      pi = await this.stripe.paymentIntents.create({
        amount, currency: "usd", customer: customerId, payment_method: paymentMethodId,
        payment_method_types: ["card"], capture_method: "manual",
        metadata: { rideId, riderId: data.riderId, paymentType: "ride_authorization" }
      }, { idempotencyKey: `ride_final_hold_${rideId}_${amount}_${previous?.id || "initial"}` });
      await ref.set({ settlementPaymentIntentId: pi.id }, { merge: true });
      // Cancellation waits until the replacement has actually authorized.
      if (previous?.status === "requires_capture") await ref.set({ supersededAuthorizationId: previous.id }, { merge: true });
    }
    if (["requires_payment_method", "requires_confirmation"].includes(pi.status)) {
      pi = await this.stripe.paymentIntents.confirm(pi.id, { payment_method: paymentMethodId, off_session: true });
    }
    if (pi.status === "requires_action") throw failure("authentication_required", 402, { clientSecret: pi.client_secret, paymentIntentId: pi.id });
    if (pi.status === "processing") return pi;
    if (pi.status !== "requires_capture") throw failure("authorization_not_capturable");
    // Store the ID before capture; every recovery retrieves this same intent.
    await ref.set({ settlementPaymentIntentId: pi.id }, { merge: true });
    const current = (await ref.get()).data();
    const oldId = current.supersededAuthorizationId;
    if (oldId && oldId !== pi.id) {
      const old = await this.stripe.paymentIntents.retrieve(oldId);
      if (old.status === "requires_capture") await this.stripe.paymentIntents.cancel(oldId, {}, { idempotencyKey: `release_${oldId}` });
    }
    pi = await this.stripe.paymentIntents.capture(pi.id, { amount_to_capture: amount }, { idempotencyKey: `ride_capture_${rideId}_${pi.id}` });
    await ref.set({ authorizationStatus: "captured" }, { merge: true });
    return pi;
  }
}
module.exports = { RideAuthorizationService };
