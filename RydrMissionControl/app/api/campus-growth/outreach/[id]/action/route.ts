import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { writeAuditLog } from "@/lib/auditLog";
import { campusCollections, cleanLongText } from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const ACTIONS = ["approve", "deny", "mark_sent", "mark_replied", "reset"] as const;

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body || !ACTIONS.includes(body.action)) {
    return NextResponse.json({ error: "Invalid outreach action." }, { status: 400 });
  }

  const ref = adminDb.collection(campusCollections.outreach).doc(params.id);
  const snap = await ref.get();
  if (!snap.exists) return NextResponse.json({ error: "Outreach draft not found." }, { status: 404 });

  const update = actionUpdate(body.action, body.reason, session.email ?? session.uid);
  await ref.update(update);

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: `Campus Outreach ${body.action}`,
    targetType: "campusOutreachDraft",
    targetId: params.id,
    metadata: { status: update.status, reason: update.denialReason }
  });

  return NextResponse.json({ ok: true, status: update.status });
}

function actionUpdate(action: (typeof ACTIONS)[number], reason: unknown, reviewer: string) {
  if (action === "approve") {
    return {
      status: "approved",
      denialReason: FieldValue.delete(),
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: reviewer,
      updatedAt: FieldValue.serverTimestamp()
    };
  }
  if (action === "deny") {
    return {
      status: "denied",
      denialReason: cleanLongText(reason, 1000) || "Denied by admin.",
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: reviewer,
      updatedAt: FieldValue.serverTimestamp()
    };
  }
  if (action === "mark_sent") {
    return {
      status: "sent",
      sentAt: FieldValue.serverTimestamp(),
      sentBy: reviewer,
      updatedAt: FieldValue.serverTimestamp()
    };
  }
  if (action === "mark_replied") {
    return {
      status: "replied",
      repliedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp()
    };
  }
  return {
    status: "draft",
    denialReason: FieldValue.delete(),
    reviewedAt: FieldValue.delete(),
    reviewedBy: FieldValue.delete(),
    sentAt: FieldValue.delete(),
    sentBy: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp()
  };
}
