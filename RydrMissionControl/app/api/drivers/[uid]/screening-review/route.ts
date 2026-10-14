import { NextRequest, NextResponse } from "next/server";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
export async function POST(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Admin access required" }, { status: 401 });
  const { uid } = await props.params;
  const input = await request.json();
  const reportReference = typeof input.reportReference === "string" ? input.reportReference.trim().slice(0, 500) : "";
  const completed = typeof input.completedDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(input.completedDate) ? Date.parse(`${input.completedDate}T12:00:00Z`) : NaN;
  if (input.passed !== true || !reportReference || !Number.isFinite(completed) || completed > Date.now() || completed + 366 * 86400000 <= Date.now()) return NextResponse.json({ error: "A reviewed passing report and current completion date are required" }, { status: 422 });
  if (new Date(completed).toISOString().slice(0, 10) !== input.completedDate) return NextResponse.json({ error: "Invalid completion date" }, { status: 422 });
  const ref = adminDb.collection("drivers").doc(uid);
  await adminDb.runTransaction(async tx => {
    const [snap, config] = await Promise.all([tx.get(ref), tx.get(adminDb.collection("platformConfig").doc("driverCompliance"))]);
    if (!snap.exists) throw new Error("Driver not found");
    tx.update(ref, { backgroundScreening: { status: "passed", provider: "manual_report_review", reportReference, completedAt: Timestamp.fromMillis(completed), validUntil: Timestamp.fromMillis(completed + 366 * 86400000), requirementVersion: String(config.data()?.backgroundCheckRequirementVersion ?? "open-pilot-v1"), reviewedBy: session.uid, reviewedAt: FieldValue.serverTimestamp() }, backgroundCheckStatus: "passed", backgroundCheckPassed: true, backgroundCheckCompletedAt: Timestamp.fromMillis(completed), betaBackgroundCheckBypassEnabled: false, updatedAt: FieldValue.serverTimestamp() });
  });
  await writeAuditLog({ adminUid: session.uid, adminEmail: session.email ?? undefined, action: "Passing background screening report verified", targetType: "driver", targetId: uid, metadata: { completedDate: input.completedDate } });
  return NextResponse.json({ ok: true });
}
