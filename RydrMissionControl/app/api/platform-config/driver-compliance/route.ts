import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
export async function PATCH(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Admin access required" }, { status: 401 });
  const body = await request.json();
  if (typeof body.backgroundChecksRequired !== "boolean") return NextResponse.json({ error: "Choose whether checks are required" }, { status: 400 });
  const policy = { backgroundChecksRequired: body.backgroundChecksRequired, backgroundCheckRequirementVersion: "open-pilot-v1", updatedBy: session.uid, updatedAt: FieldValue.serverTimestamp() };
  await adminDb.collection("platformConfig").doc("driverCompliance").set(policy, { merge: true });
  await writeAuditLog({ adminUid: session.uid, adminEmail: session.email ?? undefined, action: policy.backgroundChecksRequired ? "Open pilot background screening required for all drivers" : "Beta background screening deferral enabled", targetType: "platformConfig", targetId: "driverCompliance", metadata: { required: policy.backgroundChecksRequired, requirementVersion: policy.backgroundCheckRequirementVersion } });
  return NextResponse.json({ ok: true });
}
