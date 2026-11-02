import {currentWorkspace} from "../services/workspaceRuntime";
import {workspaceServiceURL} from "../services/workspacePolicy";
import fetch from "node-fetch";
import type { DocumentReference } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { onDocumentCreated, onDocumentWritten, onSchedule } from "../workspaceFunctions";
import { db, FieldValue } from "../admin";

const internalToken = defineSecret("RYDR_INTERNAL_SERVICE_TOKEN");
const stripeBackendURL = defineString("RYDR_STRIPE_BACKEND_URL", {
  default: "https://rydr-stripe-backend.onrender.com"
});

async function updatePaymentJob(ref: DocumentReference, update: Record<string, unknown>): Promise<boolean> {
  return db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (["succeeded", "resolved", "cancelled"].includes(snap.data()?.status)) return false;
    tx.set(ref, update, { merge: true });
    return true;
  });
}

export const onPaymentJobCreated = onDocumentCreated(
  {
    document: "paymentJobs/{rideId}",
    secrets: [internalToken],
    retry: true
  },
  async (event) => {
    const job = event.data?.data();
    if (!job || job.status === "succeeded") return;
    const rideId = event.params.rideId;
    const jobRef = db.collection("paymentJobs").doc(rideId);
    const acquired = await updatePaymentJob(jobRef, {
      status: "processing",
      attemptCount: FieldValue.increment(1),
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp()
    });
    if (!acquired) return;

    const response = await fetch(`${workspaceServiceURL(stripeBackendURL.value(),currentWorkspace())}/internal/rides/${encodeURIComponent(rideId)}/charge`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-rydr-internal-token": internalToken.value()
      },
      body: "{}"
    });
    const body = await response.json().catch(() => ({})) as Record<string, unknown>;
    if (!response.ok && body.error !== "ride_already_paid") {
      await updatePaymentJob(jobRef, {
        status: "failed",
        lastError: String(body.error ?? `HTTP ${response.status}`).slice(0, 500),
        updatedAt: FieldValue.serverTimestamp()
      });
      // Card declines and other 4xx responses require rider action and must not
      // create an endless event retry loop. Retry only transient failures.
      if (response.status === 429 || response.status >= 500) {
        throw new Error(`Payment dispatch failed for ${rideId}: ${response.status}`);
      }
      return;
    }
    const paymentStatus = String(body.status ?? "");
    const completed = body.error === "ride_already_paid" || paymentStatus === "succeeded";
    await updatePaymentJob(jobRef, {
      status: paymentStatus === "resolved" ? "resolved" : completed ? "succeeded" : "dispatched",
      ...(paymentStatus === "resolved" ? { resolutionType: body.resolutionType, resolvedAt: FieldValue.serverTimestamp() } : {}),
      paymentIntentId: body.paymentIntentId ?? null,
      ...(completed ? { completedAt: FieldValue.serverTimestamp() } : {}),
      updatedAt: FieldValue.serverTimestamp()
    });
  }
);


// Financial settlement, not client ride updates, is the reward source of truth.
export const onPaidRidePromotionSettlement = onDocumentWritten({
  document: "rides/{rideId}/financial/outcome", secrets: [internalToken], retry: true
}, async event => {
  const after = event.data?.after.data();
  if (after?.status !== "paid" || after.outcomeType !== "completed") return;
  const rideId = event.params.rideId;
  const response = await fetch(`${workspaceServiceURL(stripeBackendURL.value(),currentWorkspace())}/internal/rides/${encodeURIComponent(rideId)}/promotions/settle`, {
    method: "POST", headers: { "content-type": "application/json", "x-rydr-internal-token": internalToken.value() }, body: "{}", timeout: 55000
  });
  if (!response.ok) throw new Error(`Promotion settlement dispatch failed: ${response.status}`);
});
export const onAuthorizationReleaseJobCreated = onDocumentCreated(
  { document: "authorizationReleaseJobs/{rideId}", secrets: [internalToken], retry: true },
  async (event) => {
    const rideId = String(event.data?.data()?.rideId || event.params.rideId);
    const response = await fetch(`${workspaceServiceURL(stripeBackendURL.value(),currentWorkspace())}/internal/rides/${encodeURIComponent(rideId)}/release-authorization`, {
      method: "POST", headers: { "content-type": "application/json", "x-rydr-internal-token": internalToken.value() }, body: "{}"
    });
    if (!response.ok) throw new Error(`Authorization release failed: ${response.status}`);
    await event.data?.ref.set({ status: "succeeded", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
);

const rideBackendURL = defineString("RYDR_BACKEND_URL", { default: "https://rydr-backend.onrender.com" });
export const maintainRidePayments = onSchedule(
  { schedule: "every 5 minutes", secrets: [internalToken], retryCount: 3, timeoutSeconds: 300 },
  async () => {
    const staleAt = new Date(Date.now() - 2 * 60000);
    const [pending, transfers] = await Promise.all([
      db.collection("rides").where("paymentStatus", "in", ["pending", "processing"]).where("updatedAt", "<=", staleAt).limit(100).get(),
      db.collection("rides").where("promoSubsidyTransferStatus", "in", ["failed", "pending_driver_connect_account"]).limit(100).get()
    ]);
    const rides = new Map([...pending.docs, ...transfers.docs].map(doc => [doc.id, doc]));
    for (const [rideId] of rides) {
      const response = await fetch(`${workspaceServiceURL(stripeBackendURL.value(),currentWorkspace())}/internal/rides/${encodeURIComponent(rideId)}/charge`, {
        method: "POST", headers: { "content-type": "application/json", "x-rydr-internal-token": internalToken.value() }, body: "{}", timeout: 30000
      });
      if (response.status >= 500 || response.status === 429) throw new Error(`Payment reconciliation failed: ${response.status}`);
      const result = await response.json().catch(() => ({})) as Record<string, unknown>;
      if (result.status === "succeeded" || result.error === "ride_already_paid") {
        await db.collection("paymentJobs").doc(rideId).set({ status: "succeeded", completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      }
    }
  }
);
export const maintainStandardRides = onSchedule(
  { schedule: "every 1 minutes", secrets: [internalToken], retryCount: 3 },
  async () => {
    const response = await fetch(`${workspaceServiceURL(rideBackendURL.value(),currentWorkspace())}/rides/internal/maintenance`, {
      method: "POST", headers: { "content-type": "application/json", "x-rydr-internal-token": internalToken.value() }, body: "{}", timeout: 30000
    });
    if (!response.ok) throw new Error(`Ride maintenance failed: ${response.status}`);
  }
);
