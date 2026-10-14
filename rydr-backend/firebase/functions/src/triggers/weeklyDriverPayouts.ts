import { createHash } from "crypto";
import fetch from "node-fetch";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { db, FieldValue } from "../admin";
const token = defineSecret("RYDR_INTERNAL_SERVICE_TOKEN");
const stripeURL = defineString("RYDR_STRIPE_BACKEND_URL", { default: "https://rydr-stripe-backend.onrender.com" });

type StripeMode = "test" | "live";
async function currentStripeMode(): Promise<StripeMode> {
  const response=await fetch(`${stripeURL.value().replace(/\/$/, "")}/internal/stripe-mode`,{headers:{"x-rydr-internal-token":token.value()},timeout:10000});
  if(!response.ok)throw new Error(`Stripe mode unavailable: HTTP ${response.status}`);
  const state=await response.json() as {mode?: string;status?: string};
  if(state.status!=="ready" || (state.mode!=="test" && state.mode!=="live"))throw new Error("Stripe mode not ready");
  return state.mode;
}
export function modeAccountId(data: Record<string, any>,mode: StripeMode): string | null {
  const saved=data.stripeProfiles?.[mode];
  const source=saved??((data.stripeMode===mode || (!data.stripeMode && mode==="test"))?data:{});
  return typeof source.stripeAccountId==="string"?source.stripeAccountId:null;
}

export function mondayDate(instant: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(instant);
  const value = (type: string) => parts.find(p => p.type === type)!.value;
  const day = new Date(`${value("year")}-${value("month")}-${value("day")}T00:00:00Z`);
  day.setUTCDate(day.getUTCDate() - (day.getUTCDay() + 6) % 7);
  return day.toISOString().slice(0, 10);
}
export const queueMondayDriverPayouts = onSchedule({ schedule: "0 9 * * 1", timeZone: "America/New_York", retryCount: 3, timeoutSeconds: 540, secrets: [token] }, async event => {
  // Original schedule time makes repeated delivery target the same week.
  const mode=await currentStripeMode();
  const weekDate = mondayDate(new Date(event.scheduleTime));
  const runRef = db.collection("weeklyPayoutRuns").doc(`${mode}-${weekDate}`);
  await runRef.set({ status: "queuing", stripeMode: mode, weekDate, startedAt: FieldValue.serverTimestamp() }, { merge: true });
  let cursor: string | undefined;
  let scanned = 0;
  let created = 0;
  do {
    let query = db.collection("drivers").orderBy("__name__").limit(250);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const driver of page.docs) {
      scanned++;
      const data = driver.data();
      const accountId = modeAccountId(data,mode);
      if (!accountId && data.driverApprovalStatus !== "approved" && data.approvalStatus !== "approved" && data.isApproved !== true) continue;
      // Preserve existing test-job keys so a retried week cannot pay twice.
      const id = createHash("sha256").update(`${mode === "live" ? "live:" : ""}${accountId ?? `driver-${driver.id}`}:weekly:${weekDate}`).digest("hex");
      try {
        await db.collection("driverPayouts").doc(id).create({ driverId: driver.id, accountId, weekDate, stripeMode: mode, kind: "weekly", status: "queued", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
        created++;
      } catch (error) { if ((error as { code?: number }).code !== 6) throw error; }
    }
    cursor = page.size === 250 ? page.docs[page.size - 1].id : undefined;
  } while (cursor);
  await runRef.set({ status: "queued", scanned, created, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
});

export const dispatchWeeklyDriverPayout = onDocumentCreated({ document: "driverPayouts/{jobId}", secrets: [token], retry: true, timeoutSeconds: 180, maxInstances: 2, concurrency: 1 }, async event => {
  const job = event.data?.data();
  if (job?.kind !== "weekly") return;
  const mode=await currentStripeMode();
  if((job.stripeMode??"test")!==mode)return;
  const ref = event.data!.ref;
  const current = (await ref.get()).data();
  if (!current || current.status !== "queued") return;
  let response;
  try {
    response = await fetch(`${stripeURL.value().replace(/\/$/, "")}/internal/payout-jobs/${event.params.jobId}/process`, { method: "POST", timeout: 50000, headers: { "content-type": "application/json", "x-rydr-internal-token": token.value() }, body: "{}" });
  } catch (error) {
    await ref.set({ needsReview: true, reasonCode: "payout_dispatch_unreachable", reason: "Weekly payout dispatcher could not reach the Stripe backend. Automatic dispatch will retry; no additional payout is initiated by this flag.", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw error;
  }
  if (response.status === 409 || response.status === 429 || response.status >= 500) {
    await ref.set({ needsReview: true, reasonCode: "payout_dispatch_retry", reason: `Weekly payout dispatch requires retry (HTTP ${response.status})`, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw new Error(`Weekly payout dispatch requires retry (HTTP ${response.status})`);
  }
  if (!response.ok) await ref.set({ status: "needs_review", needsReview: true, reasonCode: "payout_dispatch_configuration", reason: `Stripe backend rejected payout dispatch (HTTP ${response.status})`, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
});

// No money movement: refresh known payouts and surface interrupted work.
export const reconcileDriverPayouts = onSchedule({ schedule: "every 30 minutes", secrets: [token], timeoutSeconds: 540 }, async () => {
  const mode=await currentStripeMode();
  for (const status of ["processing", "pending", "needs_review"]) {
    const cursorRef = db.collection("platformConfig").doc(`payoutReconcile-${mode}-${status}`);
    const cursor = (await cursorRef.get()).data()?.cursor;
    let query = db.collection("driverPayouts").where("status", "==", status).orderBy("__name__").limit(20);
    if (typeof cursor === "string") query = query.startAfter(cursor);
    const jobs = await query.get();
    for (const job of jobs.docs) {
      if((job.data().stripeMode??"test")!==mode)continue;
      const updated = job.data().updatedAt?.toMillis?.() ?? 0;
      if (status === "processing" && Date.now() - updated < 10 * 60 * 1000) continue;
      try {
        const response = await fetch(`${stripeURL.value().replace(/\/$/, "")}/internal/payout-jobs/${job.id}/reconcile`, { method: "POST", timeout: 5000, headers: { "content-type": "application/json", "x-rydr-internal-token": token.value() }, body: "{}" });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
      } catch (error) {
        console.error("Payout reconciliation failed", job.id, error instanceof Error ? error.message : "unknown");
        await job.ref.set({ needsReview: true, reasonCode: "payout_reconciliation_unavailable", reason: "Could not refresh this payout's Stripe status. No new payout was initiated.", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      }
    }
    await cursorRef.set({ cursor: jobs.size === 20 ? jobs.docs[jobs.size - 1].id : null, updatedAt: FieldValue.serverTimestamp() });
  }
});
