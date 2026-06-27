import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

type ReportAction = "dismiss" | "escalate" | "suspend_driver" | "suspend_rider";

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { action, reason } = (await request.json()) as { action: ReportAction; reason?: string };

  const reportRef = adminDb.collection("safetyReports").doc(params.id);
  const reportSnap = await reportRef.get();
  if (!reportSnap.exists) return NextResponse.json({ error: "Report not found" }, { status: 404 });
  const report = reportSnap.data() as { driverId?: string; riderId?: string };

  if (action === "dismiss") {
    await reportRef.set({ status: "dismissed" }, { merge: true });
  } else if (action === "escalate") {
    await reportRef.set({ status: "escalated" }, { merge: true });
  } else if (action === "suspend_driver" && report.driverId) {
    await adminDb.collection("drivers").doc(report.driverId).set({ driverApprovalStatus: "rejected", isApproved: false }, { merge: true });
    await reportRef.set({ status: "escalated" }, { merge: true });
  } else if (action === "suspend_rider" && report.riderId) {
    await adminDb.collection("riders").doc(report.riderId).set({ accountStatus: "suspended" }, { merge: true });
    await reportRef.set({ status: "escalated" }, { merge: true });
  } else {
    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: `Report ${action}`,
    targetType: "report",
    targetId: params.id,
    reason
  });

  return NextResponse.json({ ok: true });
}
