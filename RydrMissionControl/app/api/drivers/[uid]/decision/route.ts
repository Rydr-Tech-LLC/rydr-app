import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { evaluateDriverRequirements, type DriverRecord } from "@/lib/types";

type Decision = "approved" | "needs_attention" | "rejected";

const ACTION_LABEL: Record<Decision, string> = {
  approved: "Driver Approved",
  needs_attention: "Needs Attention",
  rejected: "Driver Rejected"
};

// Privileged write path for the three Driver Review actions. Runs entirely
// server-side via the Admin SDK (bypasses Firestore client rules, which
// correctly block clients from ever setting `driverApprovalStatus` /
// `approvedAt` / `approvedBy` themselves) and re-checks the admin session
// from the cookie rather than trusting anything the browser sends except
// which button was clicked.
export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { decision, reason } = (await request.json()) as { decision: Decision; reason?: string };
  if (!["approved", "needs_attention", "rejected"].includes(decision)) {
    return NextResponse.json({ error: "Invalid decision" }, { status: 400 });
  }

  const driverRef = adminDb.collection("drivers").doc(params.uid);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) {
    return NextResponse.json({ error: "Driver not found" }, { status: 404 });
  }

  if (decision === "approved") {
    const { canApprove, missing } = evaluateDriverRequirements(driverSnap.data() as DriverRecord);
    if (!canApprove) {
      return NextResponse.json(
        { error: `Cannot approve — missing: ${missing.join(", ")}` },
        { status: 422 }
      );
    }
  }

  const update: Record<string, unknown> = {
    driverApprovalStatus: decision,
    isApproved: decision === "approved"
  };

  if (decision === "approved") {
    update.approvedAt = FieldValue.serverTimestamp();
    update.approvedBy = session.uid;
  }
  if (decision === "rejected" && reason) {
    update.rejectionReason = reason;
  }

  await driverRef.set(update, { merge: true });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: ACTION_LABEL[decision],
    targetType: "driver",
    targetId: params.uid,
    reason
  });

  return NextResponse.json({ ok: true });
}
