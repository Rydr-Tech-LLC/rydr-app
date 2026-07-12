import { NextRequest, NextResponse } from "next/server";
import { writeAuditLog } from "@/lib/auditLog";
import {
  campusCollections,
  cleanEmail,
  cleanLongText,
  cleanText,
  listAmbassadors,
  serverTimestamps,
  splitTags,
  type AmbassadorStatus
} from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const STATUSES: AmbassadorStatus[] = ["prospect", "interview", "accepted", "active", "inactive"];

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const ambassadors = await listAmbassadors();
  return NextResponse.json({ ambassadors });
}

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid ambassador payload." }, { status: 400 });

  const name = cleanText(body.name, 160);
  const email = cleanEmail(body.email);
  if (!name || !email) return NextResponse.json({ error: "Name and valid email are required." }, { status: 400 });

  const campus = await loadCampus(body.campusId);
  const status = STATUSES.includes(body.status) ? body.status : "prospect";

  const doc = await adminDb.collection(campusCollections.ambassadors).add({
    campusId: campus.id,
    campusName: campus.name,
    name,
    email,
    status,
    sourceLeadId: cleanText(body.sourceLeadId, 160),
    goals: splitTags(body.goals),
    notes: cleanLongText(body.notes, 3000),
    createdBy: session.email ?? session.uid,
    ...serverTimestamps()
  });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Campus Ambassador Candidate Created",
    targetType: "campusAmbassador",
    targetId: doc.id,
    metadata: { name, campusName: campus.name, status }
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
