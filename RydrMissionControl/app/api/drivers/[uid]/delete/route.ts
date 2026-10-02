import { randomUUID } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { deleteAccount } from "@/lib/accountDeletion";

// Admin-initiated hard deletion. The shared account-deletion service owns
// Stripe cleanup, Auth removal, every Rider/Driver profile attached to the
// uid, phone indexes, notification tokens, and driver presence projections.
export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { reason } = (await request.json().catch(() => ({}))) as { reason?: string };

  try {
    const deletionResult = await deleteAccount({
      uid: params.uid,
      adminUid: session.uid,
      requestId: randomUUID(),
      mode: "hard"
    });

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Driver Deleted (Hard Delete)",
      targetType: "driver",
      targetId: params.uid,
      reason
    });

    return NextResponse.json({ ok: true, ...deletionResult });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: message === "Account profile not found" ? 404 : 500 });
  }
}
