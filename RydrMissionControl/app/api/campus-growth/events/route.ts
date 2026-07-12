import { NextRequest, NextResponse } from "next/server";
import { writeAuditLog } from "@/lib/auditLog";
import {
  campusCollections,
  cleanLongText,
  cleanText,
  cleanUrl,
  listCampusEvents,
  parseDate,
  scoreCampusLead,
  serverTimestamps,
  splitTags,
  type LeadStatus
} from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const STATUSES: LeadStatus[] = ["new", "qualified", "queued", "contacted", "replied", "archived"];

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const events = await listCampusEvents();
  return NextResponse.json({ events });
}

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid event payload." }, { status: 400 });

  const name = cleanText(body.name, 180);
  if (!name) return NextResponse.json({ error: "Event name is required." }, { status: 400 });

  const campus = await loadCampus(body.campusId);
  const category = cleanText(body.category, 120);
  const notes = cleanLongText(body.notes, 3000);
  const opportunityScore = scoreCampusLead({ category, name, notes });
  const status = STATUSES.includes(body.status) ? body.status : "new";

  const doc = await adminDb.collection(campusCollections.events).add({
    campusId: campus.id,
    campusName: campus.name,
    name,
    venue: cleanText(body.venue, 180),
    category,
    eventUrl: cleanUrl(body.eventUrl),
    website: cleanUrl(body.website) || cleanUrl(body.eventUrl),
    description: cleanLongText(body.description, 1000),
    tags: splitTags(body.tags),
    estimatedStudentReach: Number.isFinite(Number(body.estimatedStudentReach)) ? Number(body.estimatedStudentReach) : 0,
    priorityLevel: cleanText(body.priorityLevel, 20) || "medium",
    owner: cleanText(body.owner, 120),
    relationshipStrength: cleanText(body.relationshipStrength, 40) || "cold",
    customTags: splitTags(body.customTags),
    meetingNotes: cleanLongText(body.meetingNotes, 3000),
    lastAIRecommendation: cleanText(body.lastAIRecommendation, 180),
    opportunityScore,
    status,
    source: cleanText(body.source, 160) || "public_source",
    startsAt: parseDate(body.startsAt),
    notes,
    createdBy: session.email ?? session.uid,
    ...serverTimestamps()
  });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Campus Event Lead Created",
    targetType: "campusEvent",
    targetId: doc.id,
    metadata: { name, campusName: campus.name, opportunityScore, status }
  });

  return NextResponse.json({ id: doc.id }, { status: 201 });
}

async function loadCampus(campusId: unknown) {
  const id = cleanText(campusId, 120);
  if (!id) return { id: "", name: "" };
  const snap = await adminDb.collection(campusCollections.campuses).doc(id).get();
  if (!snap.exists) return { id: "", name: "" };
  const data = snap.data() as { name?: string };
  return { id: snap.id, name: data.name ?? "" };
}
