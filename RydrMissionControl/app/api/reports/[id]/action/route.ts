import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { FieldValue } from "firebase-admin/firestore";

type ReportAction =
  | "dismiss"
  | "escalate"
  | "suspend_driver"
  | "suspend_rider"
  | "mark_unsafe_driving"
  | "mark_cleanliness"
  | "mark_phone_use"
  | "mark_unprofessional";

const penaltyActions: Partial<Record<ReportAction, { category: string; label: string; type: "safety" | "unprofessional"; severity: string }>> = {
  mark_unsafe_driving: {
    category: "unsafe_driving",
    label: "Unsafe driving",
    type: "safety",
    severity: "high"
  },
  mark_cleanliness: {
    category: "unclean_car",
    label: "Unclean car",
    type: "safety",
    severity: "standard"
  },
  mark_phone_use: {
    category: "phone_usage_while_driving",
    label: "Phone usage while driving",
    type: "safety",
    severity: "high"
  },
  mark_unprofessional: {
    category: "unprofessional_conduct",
    label: "Unprofessional conduct",
    type: "unprofessional",
    severity: "high"
  }
};

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { action, reason } = (await request.json()) as { action: ReportAction; reason?: string };

  const reportRef = adminDb.collection("safetyReports").doc(params.id);
  const reportSnap = await reportRef.get();
  if (!reportSnap.exists) return NextResponse.json({ error: "Report not found" }, { status: 404 });
  const report = reportSnap.data() as {
    driverId?: string;
    riderId?: string;
    rideId?: string;
    description?: string;
    reportType?: string;
  };

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
  } else if (penaltyActions[action] && report.driverId) {
    const penalty = penaltyActions[action]!;
    const penaltyRef = adminDb.collection("driverSafetyPenalties").doc(`${params.id}_${penalty.category}`);
    const penaltyPayload: Record<string, unknown> = {
      driverId: report.driverId,
      riderId: report.riderId ?? null,
      rideId: report.rideId ?? null,
      riderReportId: params.id,
      source: "rider_report",
      category: penalty.category,
      categoryLabel: penalty.label,
      penaltyType: penalty.type,
      severity: penalty.severity,
      status: "active",
      reviewStatus: "pending_manual_review",
      appealStatus: "not_appealed",
      analyticsReviewStatus: "pending",
      telemetryReviewRequired: true,
      description: report.description ?? report.reportType ?? penalty.label,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: session.uid,
      updatedBy: session.uid
    };
    await penaltyRef.set(penaltyPayload, { merge: true });
    if (penalty.type === "unprofessional") {
      await adminDb.collection("drivers").doc(report.driverId).set(
        {
          accountStatus: "suspended",
          safetyHold: true,
          safetyReviewStatus: "suspended",
          safetyHoldReason: penalty.label,
          safetyHoldReportId: params.id,
          safetyHoldAppliedAt: FieldValue.serverTimestamp(),
          safetyHoldAppliedBy: session.uid
        },
        { merge: true }
      );
    }
    await reportRef.set(
      {
        status: "escalated",
        driverSafetyPenaltyId: penaltyRef.id,
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );
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
