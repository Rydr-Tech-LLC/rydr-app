import { randomUUID } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { deleteAccount } from "@/lib/accountDeletion";

// Admin-initiated hard deletion. This intentionally uses the same shared
// account-deletion service as Driver deletion and the reviewed request queue.
export async function POST(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const params = await props.params;
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
      action: "Rider Deleted (Hard Delete)",
      targetType: "rider",
      targetId: params.uid,
      reason
    });

    return NextResponse.json({ ok: true, ...deletionResult });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: message === "Account profile not found" ? 404 : 500 });
  }
}
