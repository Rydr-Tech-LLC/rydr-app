import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { active, reason } = (await request.json().catch(() => ({}))) as {
    active?: boolean;
    reason?: string;
  };

  if (typeof active !== "boolean") {
    return NextResponse.json({ error: "Expected active to be true or false." }, { status: 400 });
  }

  const riderRef = adminDb.collection("riders").doc(params.uid);
  const riderSnap = await riderRef.get();
  if (!riderSnap.exists) return NextResponse.json({ error: "Rider not found." }, { status: 404 });

  if (active) {
    await riderRef.set(
      {
        badges: {
          studentAmbassador: {
            active: true,
            label: "Student Ambassador",
            description: "Campus liaison helping Rydr build a student beta testing community.",
            assetName: "StudentAmbassadorBadge",
            missionControlAssetPath: "/badges/student-ambassador-badge.svg",
            assignedAt: FieldValue.serverTimestamp(),
            assignedBy: session.uid,
            assignedByEmail: session.email ?? null
          }
        },
        betaRole: "studentAmbassador",
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );
  } else {
    await riderRef.update({
      "badges.studentAmbassador": FieldValue.delete(),
      betaRole: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp()
    });
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: active ? "Student Ambassador Badge Assigned" : "Student Ambassador Badge Removed",
    targetType: "rider",
    targetId: params.uid,
    reason
  });

  return NextResponse.json({ ok: true, active });
}
