import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { writeAuditLog } from "@/lib/auditLog";
import {
  CAMPUS_OUTREACH_BCC_EMAIL,
  CAMPUS_OUTREACH_FROM_EMAIL,
  campusCollections,
  cleanEmail,
  cleanLongText,
  type OutreachDraft
} from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getCampusGrowthSession } from "@/lib/session";
import { notificationService } from "@/src/services/notifications/NotificationService";

const ACTIONS = ["approve", "approve_and_send", "deny", "mark_sent", "mark_replied", "reset"] as const;

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getCampusGrowthSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body || !ACTIONS.includes(body.action)) {
    return NextResponse.json({ error: "Invalid outreach action." }, { status: 400 });
  }

  const ref = adminDb.collection(campusCollections.outreach).doc(params.id);
  const snap = await ref.get();
  if (!snap.exists) return NextResponse.json({ error: "Outreach draft not found." }, { status: 404 });
  const draft = { id: snap.id, ...(snap.data() as Omit<OutreachDraft, "id">) };

  let update;
  try {
    update =
      body.action === "approve_and_send"
        ? await approveAndSendUpdate(draft, session.email ?? session.uid)
        : actionUpdate(body.action, body.reason, session.email ?? session.uid);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Unable to send outreach email." }, { status: 400 });
  }
  await ref.update(update);

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: `Campus Outreach ${body.action}`,
    targetType: "campusOutreachDraft",
    targetId: params.id,
    metadata: {
      status: update.status,
      reason: update.denialReason,
      providerMessageId: "providerMessageId" in update ? update.providerMessageId : undefined,
      recipientEmail: draft.recipientEmail
    }
  });

  return NextResponse.json({ ok: true, status: update.status });
}

async function approveAndSendUpdate(draft: OutreachDraft, reviewer: string) {
  if ((draft.channel ?? "email") !== "email") {
    throw new Error("Only email drafts can be sent from Mission Control. Use Mark Sent Manually for other channels.");
  }

  const to = cleanEmail(draft.recipientEmail);
  if (!to) throw new Error("A valid recipient email is required before this draft can be sent.");
  if (!draft.subject?.trim()) throw new Error("A subject is required before this draft can be sent.");
  if (!draft.body?.trim()) throw new Error("A message body is required before this draft can be sent.");

  const result = await notificationService.sendGenericEmail({
    from: draft.fromEmail || CAMPUS_OUTREACH_FROM_EMAIL,
    to,
    bcc: draft.bccEmail || CAMPUS_OUTREACH_BCC_EMAIL,
    subject: draft.subject,
    title: draft.subject,
    body: draft.body,
    eyebrow: "Rydr Campus Outreach"
  });

  if (!result.ok) {
    throw new Error(result.error ?? "Resend could not send this outreach email.");
  }

  return {
    status: "sent",
    denialReason: FieldValue.delete(),
    reviewedAt: FieldValue.serverTimestamp(),
    reviewedBy: reviewer,
    sentAt: FieldValue.serverTimestamp(),
    sentBy: reviewer,
    sentVia: "resend",
    providerMessageId: result.providerMessageId ?? null,
    fromEmail: draft.fromEmail || CAMPUS_OUTREACH_FROM_EMAIL,
    bccEmail: draft.bccEmail || CAMPUS_OUTREACH_BCC_EMAIL,
    updatedAt: FieldValue.serverTimestamp()
  };
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
