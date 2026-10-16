import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { getWorkspaceDb, adminStorage } from "@/lib/firebaseAdmin";
import { buildVehicleId } from "@/lib/vehicleLibrary";
import { writeAuditLog } from "@/lib/auditLog";

export async function POST(request: NextRequest, context: { params: Promise<{ jobId: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const { jobId } = await context.params;
  if (!/^[a-f0-9]{64}$/.test(jobId)) return NextResponse.json({ error: "Invalid job" }, { status: 400 });
  const body = await request.json().catch(() => null);
  if (!["retry", "dismiss", "use_library"].includes(body?.action)) return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  const ref = (await getWorkspaceDb()).collection("vehicleImageJobs").doc(jobId);
  try {
    await (await getWorkspaceDb()).runTransaction(async tx => {
      const snap = await tx.get(ref); const job = snap.data();
      if (!job || job.status !== "needs_review") throw new Error("Only an unresolved review can be changed");
      let update: Record<string, unknown> = { status: body.action === "retry" ? "queued" : "dismissed",
        reviewedBy: session.uid, updatedAt: FieldValue.serverTimestamp() };
      if (body.action === "use_library") {
        const q = job.query;
        const vehicleId = buildVehicleId(q.make, q.model, q.year, q.year, q.trim);
        const library = (await tx.get((await getWorkspaceDb()).collection("vehicleLibrary").doc(vehicleId))).data();
        const path = library?.colorImages?.[q.color];
        if (typeof path !== "string" || !path.startsWith("vehicle-library/")) throw new Error("Upload this vehicle's color image to the library first");
        update = { ...update, status: "completed", vehicleId, storagePath: path,
          imageUrl: `https://storage.googleapis.com/${adminStorage.bucket().name}/${encodeURI(path)}`,
          reason: "Resolved with a Mission Control library image" };
      }
      if (body.action === "retry") update.reason = "Retry requested by administrator";
      if (body.action === "dismiss") update.reason = "Dismissed by administrator; future requests will not repeat the search";
      tx.update(ref, update);
    });
    await writeAuditLog({ adminUid: session.uid, adminEmail: session.email ?? undefined,
      action: `Vehicle Image Review: ${body.action}`, targetType: "vehicleImageJobs", targetId: jobId });
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Review action failed" }, { status: 409 });
  }
}
