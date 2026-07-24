import { NextRequest, NextResponse } from "next/server";
import { writeAuditLog } from "@/lib/auditLog";
import {
  campusCollections,
  cleanLongText,
  cleanText,
  listCampuses,
  serverTimestamps,
  splitTags,
  type CampusPriority,
  type CampusStatus
} from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getCampusGrowthSession } from "@/lib/session";

const PRIORITIES: CampusPriority[] = ["low", "medium", "high"];
const STATUSES: CampusStatus[] = ["researching", "active", "paused", "archived"];

export async function GET() {
  const session = await getCampusGrowthSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const campuses = await listCampuses();
  return NextResponse.json({ campuses });
}

export async function POST(request: NextRequest) {
  const session = await getCampusGrowthSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid campus payload." }, { status: 400 });

  const name = cleanText(body.name, 140);
  if (!name) return NextResponse.json({ error: "Campus name is required." }, { status: 400 });

  const priority = PRIORITIES.includes(body.priority) ? body.priority : "medium";
  const status = STATUSES.includes(body.status) ? body.status : "researching";
  const doc = await adminDb.collection(campusCollections.campuses).add({
    name,
    city: cleanText(body.city, 100),
    state: cleanText(body.state, 40).toUpperCase(),
    market: cleanText(body.market, 80),
    priority,
    status,
    owner: cleanText(body.owner, 120),
    notes: cleanLongText(body.notes, 3000),
    tags: splitTags(body.tags),
    createdBy: session.email ?? session.uid,
    ...serverTimestamps()
  });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Campus Target Created",
    targetType: "campusTarget",
    targetId: doc.id,
    metadata: { name, priority, status }
  });

  return NextResponse.json({ id: doc.id }, { status: 201 });
}
