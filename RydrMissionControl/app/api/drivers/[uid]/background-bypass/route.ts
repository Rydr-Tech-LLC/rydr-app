import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { reason } = (await request.json().catch(() => ({}))) as { reason?: string };
  const driverRef = adminDb.collection("drivers").doc(params.uid);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) {
    return NextResponse.json({ error: "Driver not found" }, { status: 404 });
  }

  await driverRef.set(
    {
      backgroundCheckStatus: "beta_deferred",
      backgroundCheckPassed: false,
      betaBackgroundCheckBypassEnabled: true,
      betaBackgroundCheckBypassedAt: FieldValue.serverTimestamp(),
      betaBackgroundCheckBypassedBy: session.uid,
      betaBackgroundCheckBypassReason: reason || "60-day beta background check deferral",
      updatedAt: FieldValue.serverTimestamp()
    },
    { merge: true }
  );

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Beta Background Check Deferred",
    targetType: "driver",
    targetId: params.uid,
    reason: reason || "60-day beta background check deferral"
  });

  return NextResponse.json({ ok: true });
}
