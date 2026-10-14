import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { db, FieldValue, Timestamp } from "../admin";
import { IMAGE_JOBS, enqueueImageJob, processImageJob, updateWaitingDrivers, matchesVehicle, validImageQuery } from "../services/vehicleImageAcquisition";
import { vehicleImageService } from "../services/vehicleImageService";
import type { VehicleImageQuery } from "../types";

const openaiKey = defineSecret("OPENAI_API_KEY");
export const onVehicleImageJobWritten = onDocumentWritten({
  document: `${IMAGE_JOBS}/{jobId}`, secrets: [openaiKey], timeoutSeconds: 540,
  memory: "512MiB", maxInstances: 2, concurrency: 1, retry: true
}, async event => {
  const job = event.data?.after.data();
  if (!job) return;
  if (job.status === "queued") await processImageJob(event.params.jobId, openaiKey.value());
  if (job.status === "completed") {
    vehicleImageService.invalidate();
    await updateWaitingDrivers(event.params.jobId, job);
  }
});

async function requestDriverImage(uid: string, vehicle: any): Promise<void> {
  if (!vehicle || ((vehicle.imageUrl || vehicle.imageURL) && !(vehicle.imageMatchTier > 1))) return;
  const query: VehicleImageQuery = { make: vehicle.make, model: vehicle.model, year: Number(vehicle.year),
    trim: vehicle.trim ?? null, color: vehicle.color, bodyStyle: vehicle.bodyStyle ?? "unknown" };
  if (!validImageQuery(query)) return;
  const lookup = await vehicleImageService.getImage(query);
  if (lookup.result?.tier !== 1) {
    await enqueueImageJob(query, uid);
    return;
  }
  const ref = db.collection("drivers").doc(uid);
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref); const current = snap.data()?.vehicle;
    if (!matchesVehicle(current, query) || ((current.imageUrl || current.imageURL) && !(current.imageMatchTier > 1))) return;
    tx.update(ref, { "vehicle.imageUrl": lookup.result!.imageUrl, "vehicle.imageURL": lookup.result!.imageUrl,
      "vehicle.imagePath": lookup.result!.storagePath, "vehicle.libraryVehicleId": lookup.result!.matchedVehicleId,
      "vehicle.libraryMatchedColor": query.color, "vehicle.imageMatchTier": 1,
      vehicleImageStatus: "matched", updatedAt: FieldValue.serverTimestamp() });
  });
}

export const onDriverVehicleImageNeeded = onDocumentWritten({ document: "drivers/{uid}", retry: true }, async event => {
  await requestDriverImage(event.params.uid, event.data?.after.data()?.vehicle);
});

// Repairs interrupted workers and backfills existing drivers in bounded pages.
// A persistent cursor makes every driver reachable, without an unbounded scan.
export const maintainVehicleImageJobs = onSchedule({ schedule: "every 15 minutes", timeoutSeconds: 300 }, async () => {
  const stale = await db.collection(IMAGE_JOBS).where("status", "==", "processing").get();
  for (const doc of stale.docs) {
    await db.runTransaction(async tx => {
      const snap = await tx.get(doc.ref); const job = snap.data();
      if (job?.status === "processing" && job.startedAt?.toMillis() < Date.now() - 15 * 60 * 1000) {
        tx.update(doc.ref, { status: "needs_review", reason: "Image worker was interrupted. Retry acquisition.", updatedAt: FieldValue.serverTimestamp() });
      }
    });
  }
  const stateRef = db.collection("platformConfig").doc("vehicleImageBackfill");
  const state = (await stateRef.get()).data();
  let query = db.collection("drivers").orderBy("__name__").limit(100);
  if (typeof state?.cursor === "string") query = query.startAfter(state.cursor);
  const drivers = await query.get();
  for (const doc of drivers.docs) {
    const v = doc.data().vehicle;
    if (!v || ((v.imageUrl || v.imageURL) && !(v.imageMatchTier > 1))) continue;
    await requestDriverImage(doc.id, v);
  }
  await stateRef.set({ cursor: drivers.size === 100 ? drivers.docs[drivers.size - 1].id : null, updatedAt: Timestamp.now() });
});
