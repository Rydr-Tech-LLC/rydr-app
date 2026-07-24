import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { writeAuditLog } from "@/lib/auditLog";
import {
  campusCollections,
  cleanLongText,
  cleanText,
  cleanUrl,
  scoreCampusLead,
  serverTimestamps,
  type DiscoveredCampusLead
} from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const ACTIONS = ["approve", "reject", "reset"] as const;

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body || !ACTIONS.includes(body.action)) {
    return NextResponse.json({ error: "Invalid discovered lead action." }, { status: 400 });
  }

  const ref = adminDb.collection(campusCollections.discoveredLeads).doc(params.id);
  const snap = await ref.get();
  if (!snap.exists) return NextResponse.json({ error: "Discovered lead not found." }, { status: 404 });
  const lead = { id: snap.id, ...(snap.data() as Omit<DiscoveredCampusLead, "id">) };

  let approvedTargetId = "";
  if (body.action === "approve") {
    approvedTargetId = await convertDiscoveredLead(lead, session.email ?? session.uid);
    await ref.update({
      reviewStatus: "approved",
      approvedTargetId,
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: session.email ?? session.uid,
      rejectionReason: FieldValue.delete()
    });
  } else if (body.action === "reject") {
    await ref.update({
      reviewStatus: "rejected",
      rejectionReason: cleanLongText(body.reason, 1000) || "Rejected by admin.",
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: session.email ?? session.uid
    });
  } else {
    await ref.update({
      reviewStatus: "pending_review",
      rejectionReason: FieldValue.delete(),
      reviewedAt: FieldValue.delete(),
      reviewedBy: FieldValue.delete(),
      approvedTargetId: FieldValue.delete()
    });
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: `AI Campus Lead ${body.action}`,
    targetType: "campusDiscoveredLead",
    targetId: params.id,
    metadata: { approvedTargetId, kind: lead.kind, campusName: lead.campusName, name: lead.name }
  });

  return NextResponse.json({ ok: true, approvedTargetId });
}

async function convertDiscoveredLead(lead: DiscoveredCampusLead, createdBy: string) {
  if (lead.kind === "event") {
    const doc = await adminDb.collection(campusCollections.events).add({
      campusId: lead.campusId ?? "",
      campusName: lead.campusName ?? "",
      name: cleanText(lead.name, 180),
      venue: cleanText(lead.venue, 180),
      category: cleanText(lead.category, 120),
      eventUrl: cleanUrl(lead.sourceUrl),
      website: cleanUrl(lead.website) || cleanUrl(lead.sourceUrl),
      description: cleanLongText(lead.description, 1000),
      tags: lead.tags ?? [],
      estimatedStudentReach: lead.estimatedStudentReach ?? 0,
      discoveryConfidence: lead.discoveryConfidence ?? 0,
      scoreReason: lead.scoreReason ?? "",
      aiSummary: lead.summary ?? "",
      aiRecommendations: lead.aiRecommendations ?? [],
      interactionTimeline: lead.interactionTimeline ?? [],
      conversationHistory: lead.conversationHistory ?? [],
      meetingNotes: lead.meetingNotes ?? "",
      attachments: lead.attachments ?? [],
      customTags: lead.customTags ?? lead.tags ?? [],
      priorityLevel: lead.priorityLevel ?? "medium",
      owner: lead.owner ?? "",
      followUpReminderAt: lead.followUpReminderAt ?? null,
      relationshipStrength: lead.relationshipStrength ?? "cold",
      lastAIRecommendation: lead.lastAIRecommendation ?? lead.aiRecommendations?.[0] ?? "",
      opportunityScore: clamp(Number(lead.relevanceScore) || 0, 1, 100),
      status: "new",
      source: lead.sourceType || "ai_discovered_public_source",
      notes: buildNotes(lead),
      createdBy,
      aiDiscoveredLeadId: lead.id,
      ...serverTimestamps()
    });
    return doc.id;
  }

  const doc = await adminDb.collection(campusCollections.organizations).add({
    campusId: lead.campusId ?? "",
    campusName: lead.campusName ?? "",
    name: cleanText(lead.name, 180),
    category: cleanText(lead.category, 120),
    website: cleanUrl(lead.website) || cleanUrl(lead.sourceUrl),
    publicEmail: lead.publicEmail ?? "",
    leaderName: lead.publicContactName ?? "",
    leaderTitle: lead.publicContactTitle ?? "",
    socialUrl: lead.instagramUrl || lead.tiktokUrl || lead.facebookUrl || lead.linkedInUrl || "",
    instagramUrl: lead.instagramUrl ?? "",
    linkedInUrl: lead.linkedInUrl ?? "",
    discordUrl: lead.discordUrl ?? "",
    facebookUrl: lead.facebookUrl ?? "",
    tiktokUrl: lead.tiktokUrl ?? "",
    meetingSchedule: lead.meetingSchedule ?? "",
    description: cleanLongText(lead.description, 1000),
    tags: lead.tags ?? [],
    estimatedStudentReach: lead.estimatedStudentReach ?? 0,
    discoveryConfidence: lead.discoveryConfidence ?? 0,
    scoreReason: lead.scoreReason ?? "",
    aiSummary: lead.summary ?? "",
    aiRecommendations: lead.aiRecommendations ?? [],
    interactionTimeline: lead.interactionTimeline ?? [],
    conversationHistory: lead.conversationHistory ?? [],
    meetingNotes: lead.meetingNotes ?? "",
    attachments: lead.attachments ?? [],
    customTags: lead.customTags ?? lead.tags ?? [],
    priorityLevel: lead.priorityLevel ?? "medium",
    owner: lead.owner ?? "",
    followUpReminderAt: lead.followUpReminderAt ?? null,
    relationshipStrength: lead.relationshipStrength ?? "cold",
    lastAIRecommendation: lead.lastAIRecommendation ?? lead.aiRecommendations?.[0] ?? "",
    relevanceScore: clamp(Number(lead.relevanceScore) || scoreCampusLead({ name: lead.name, category: lead.category, notes: lead.summary }), 1, 100),
    status: "new",
    source: lead.sourceType || "ai_discovered_public_source",
    notes: buildNotes(lead),
    createdBy,
    aiDiscoveredLeadId: lead.id,
    ...serverTimestamps()
  });
  return doc.id;
}

function buildNotes(lead: DiscoveredCampusLead) {
  return cleanLongText(
    [
      lead.summary ? `AI summary: ${lead.summary}` : "",
      lead.description ? `Description: ${lead.description}` : "",
      lead.scoreReason ? `Score reason: ${lead.scoreReason}` : "",
      lead.aiRecommendations?.length ? `AI recommendations: ${lead.aiRecommendations.join(", ")}` : "",
      lead.outreachAngle ? `Outreach angle: ${lead.outreachAngle}` : "",
      lead.meetingSchedule ? `Meeting schedule: ${lead.meetingSchedule}` : "",
      lead.sourceTitle ? `Source title: ${lead.sourceTitle}` : "",
      lead.sourceSnippet ? `Source snippet: ${lead.sourceSnippet}` : "",
      lead.startsAtText ? `Event timing: ${lead.startsAtText}` : ""
    ]
      .filter(Boolean)
      .join("\n\n"),
    4000
  );
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}
