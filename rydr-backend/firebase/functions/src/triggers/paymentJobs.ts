import {currentWorkspace} from "../services/workspaceRuntime";
import {workspaceServiceURL} from "../services/workspacePolicy";
import fetch from "node-fetch";
import { defineSecret, defineString } from "firebase-functions/params";
import { onDocumentCreated, onDocumentWritten } from "../workspaceFunctions";
import { db, FieldValue } from "../admin";

const internalToken = defineSecret("RYDR_INTERNAL_SERVICE_TOKEN");
const stripeBackendURL = defineString("RYDR_STRIPE_BACKEND_URL", {
  default: "https://rydr-stripe-backend.onrender.com"
});

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
    await jobRef.set({
      status: "processing",
      attemptCount: FieldValue.increment(1),
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });

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
      await jobRef.set({
        status: "failed",
        lastError: String(body.error ?? `HTTP ${response.status}`).slice(0, 500),
        updatedAt: FieldValue.serverTimestamp()
      }, { merge: true });
      // Card declines and other 4xx responses require rider action and must not
      // create an endless event retry loop. Retry only transient failures.
      if (response.status === 429 || response.status >= 500) {
        throw new Error(`Payment dispatch failed for ${rideId}: ${response.status}`);
      }
      return;
    }
    const paymentStatus = String(body.status ?? "");
    const completed = body.error === "ride_already_paid" || paymentStatus === "succeeded";
    await jobRef.set({
      status: completed ? "succeeded" : "dispatched",
      paymentIntentId: body.paymentIntentId ?? null,
      ...(completed ? { completedAt: FieldValue.serverTimestamp() } : {}),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
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
