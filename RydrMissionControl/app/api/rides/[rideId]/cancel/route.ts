import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { callRydrBackendAdmin } from "@/lib/rydrBackendAdmin";

export async function POST(request: NextRequest, props: { params: Promise<{ rideId: string }> }) {
  const params = await props.params;
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => ({}))) as { reason?: string };
  const reason = typeof body.reason === "string" && body.reason.trim() ? body.reason.trim() : "Mission Control cancelled this ride.";

  let result: Record<string, unknown>;
  try {
    result = await callRydrBackendAdmin(`/rides/internal/${encodeURIComponent(params.rideId)}/admin-cancel`, session.uid, {
      reason,
      requestId: crypto.randomUUID()
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Ride cancellation failed" }, { status: 409 });
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Ride Cancelled",
    targetType: "ride",
    targetId: params.rideId,
    reason,
    metadata: {
      lifecycleStatus: result.status ?? null,
      duplicate: result.duplicate === true
    }
  });

  return NextResponse.json(result);
}
