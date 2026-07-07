import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

const TERMINAL_STATUSES = new Set(["completed", "cancelled", "riderCancelled", "driverCancelled", "adminCancelled"]);

export async function POST(request: NextRequest, { params }: { params: { rideId: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => ({}))) as { reason?: string };
  const reason = typeof body.reason === "string" && body.reason.trim() ? body.reason.trim() : "Mission Control cancelled this ride.";

  const rideRef = adminDb.collection("rides").doc(params.rideId);
  const requestRef = adminDb.collection("rideRequests").doc(params.rideId);
  const [rideSnap, requestSnap] = await Promise.all([rideRef.get(), requestRef.get()]);
  if (!rideSnap.exists) return NextResponse.json({ error: "Ride not found" }, { status: 404 });

  const ride = rideSnap.data() ?? {};
  const status = String(ride.status ?? "");
  if (TERMINAL_STATUSES.has(status)) {
    return NextResponse.json({ error: "Ride is already terminal", status }, { status: 409 });
  }

  const now = FieldValue.serverTimestamp();
  const update = {
    status: "adminCancelled",
    cancelledAt: now,
    cancelledBy: session.uid,
    cancelledByRole: "admin",
    cancellationReason: reason,
    adminCancelledAt: now,
    adminCancelledBy: session.uid,
    riderRideState: "cancelled",
    riderStatusMessage: "Support cancelled this ride. You can request another ride from the home screen.",
    driverQueueStatus: "cancelled",
    updatedAt: now
  };

  const batch = adminDb.batch();
  batch.set(rideRef, update, { merge: true });
  if (requestSnap.exists) {
    batch.set(requestRef, update, { merge: true });
  }
  await batch.commit();

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Ride Cancelled",
    targetType: "ride",
    targetId: params.rideId,
    reason,
    metadata: {
      previousStatus: status,
      riderId: typeof ride.riderId === "string" ? ride.riderId : null,
      driverId: typeof ride.driverId === "string" ? ride.driverId : null
    }
  });

  return NextResponse.json({ ok: true });
}
