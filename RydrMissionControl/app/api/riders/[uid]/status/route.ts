import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { status, reason } = (await request.json()) as { status: "active" | "suspended" | "removed"; reason?: string };
  if (!["active", "suspended", "removed"].includes(status)) {
    return NextResponse.json({ error: "Invalid status" }, { status: 400 });
  }

  await adminDb.collection("riders").doc(params.uid).set({ accountStatus: status }, { merge: true });
  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: status === "active" ? "Account Reinstated" : "Account Suspended",
    targetType: "rider",
    targetId: params.uid,
    reason
  });

  return NextResponse.json({ ok: true });
}
