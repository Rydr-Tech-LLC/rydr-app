import { NextRequest, NextResponse } from "next/server";
import { writeAuditLog } from "@/lib/auditLog";
import {
  CAMPUS_OUTREACH_BCC_EMAIL,
  CAMPUS_OUTREACH_FROM_EMAIL,
  campusCollections,
  cleanEmail,
  cleanLongText,
  cleanText,
  listOutreachDrafts,
  serverTimestamps
} from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getCampusGrowthSession } from "@/lib/session";

const TARGET_TYPES = ["organization", "event", "campus", "manual"] as const;
const CHANNELS = ["email", "instagram", "facebook", "tiktok", "linkedin", "discord", "event_invitation", "internship_invitation", "ambassador_invitation", "other"] as const;

export async function GET() {
  const session = await getCampusGrowthSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const drafts = await listOutreachDrafts();
  return NextResponse.json({ drafts });
}

export async function POST(request: NextRequest) {
  const session = await getCampusGrowthSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid outreach payload." }, { status: 400 });

  const subject = cleanText(body.subject, 180);
  const draftBody = cleanLongText(body.body, 8000);
  if (!subject || !draftBody) return NextResponse.json({ error: "Subject and body are required." }, { status: 400 });

  const channel = CHANNELS.includes(body.channel) ? body.channel : "email";
  const targetType = TARGET_TYPES.includes(body.targetType) ? body.targetType : "manual";
  const recipientEmail = cleanEmail(body.recipientEmail);
  if (channel === "email" && !recipientEmail) {
    return NextResponse.json({ error: "A valid recipient email is required for email drafts." }, { status: 400 });
  }

  const doc = await adminDb.collection(campusCollections.outreach).add({
    targetType,
    targetId: cleanText(body.targetId, 160),
    campusId: cleanText(body.campusId, 160),
    campusName: cleanText(body.campusName, 180),
    organizationName: cleanText(body.organizationName, 180),
    fromEmail: CAMPUS_OUTREACH_FROM_EMAIL,
    bccEmail: CAMPUS_OUTREACH_BCC_EMAIL,
    recipientName: cleanText(body.recipientName, 160),
    recipientEmail,
    channel,
    subject,
    body: draftBody,
    status: "draft",
    relevanceScore: Number.isFinite(Number(body.relevanceScore)) ? Number(body.relevanceScore) : 0,
    createdBy: session.email ?? session.uid,
    ...serverTimestamps()
  });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Campus Outreach Draft Created",
    targetType: "campusOutreachDraft",
    targetId: doc.id,
    metadata: { channel, targetType, subject, fromEmail: CAMPUS_OUTREACH_FROM_EMAIL, bccEmail: CAMPUS_OUTREACH_BCC_EMAIL }
  });

  return NextResponse.json({ id: doc.id }, { status: 201 });
}
