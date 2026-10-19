import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { getControlDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { currentWorkspace } from "@/lib/workspace";
import { CAMPAIGNS, seedBetaSchedule, validateAnnouncement } from "@/lib/notificationCampaigns";

export async function GET() {
  if (!await getAdminSession()) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  if (await currentWorkspace() !== "live-beta") return NextResponse.json({ error: "Open Notifications in the Live Beta workspace." }, { status: 409 });
  const adminDb = getControlDb();
  const snap = await adminDb.collection(CAMPAIGNS).orderBy("sendAt", "desc").limit(100).get();
  const heartbeat = (await adminDb.collection("notificationSystem").doc("scheduler").get()).data()?.lastRunAt;
  const schedulerReady = Boolean(heartbeat && Date.now() - heartbeat.toMillis() < 5 * 60_000);
  return NextResponse.json({ schedulerReady, campaigns: snap.docs.map(doc => ({ ...doc.data(), id: doc.id, sendAt: doc.data().sendAt.toDate().toISOString() })) });
}

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  if (await currentWorkspace() !== "live-beta") return NextResponse.json({ error: "Open Notifications in the Live Beta workspace." }, { status: 409 });
  const adminDb = getControlDb();
  const body = await request.json().catch(() => null);
  try {
    let targetId: string;
    if (body?.action === "seedBeta") {
      await seedBetaSchedule(session.uid);
      targetId = "live-beta-2026";
    } else if (body?.action === "cancel") {
      if (typeof body.id !== "string" || !/^[\w-]{1,128}$/.test(body.id)) throw new Error("Invalid announcement.");
      targetId = body.id;
      await adminDb.runTransaction(async tx => {
        const ref = adminDb.collection(CAMPAIGNS).doc(body.id);
        const snap = await tx.get(ref);
        if (!snap.exists || !["scheduled", "sending"].includes(snap.data()!.status)) throw new Error("This announcement cannot be cancelled.");
        tx.update(ref, { status: "cancelled", cancelledBy: session.uid, cancelledAt: FieldValue.serverTimestamp() });
      });
    } else {
      const data = validateAnnouncement(body);
      const ref = await adminDb.collection(CAMPAIGNS).add({ ...data, status: "scheduled", cursor: null, counts: {}, createdBy: session.uid, createdAt: FieldValue.serverTimestamp() });
      targetId = ref.id;
    }
    await writeAuditLog({ adminUid: session.uid, action: `Notification ${body?.action ?? "scheduled"}`, targetType: "notificationCampaign", targetId });
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Could not save announcement." }, { status: 400 });
  }
}
