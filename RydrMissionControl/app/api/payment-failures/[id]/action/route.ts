import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { callRydrBackendAdmin } from "@/lib/rydrBackendAdmin";

type Action = "resolve" | "write_off";

// Manual ops-side outcomes for a ride whose Stripe charge failed and where
// the in-app Retry / Update Card flow isn't going to resolve it (rider
// already paid another way, fare is being written off as a goodwill
// gesture, etc.). This never calls Stripe directly — it only updates our
// own ledger state — so it can't accidentally trigger a duplicate charge or
// refund. Real money movement (refunds) still goes through stripe-backend's
// existing webhook-driven flows.
export async function POST(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { action, reason } = (await request.json()) as { action: Action; reason?: string };
  if (!["resolve", "write_off"].includes(action)) {
    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }

  let result: Record<string, unknown>;
  try {
    result = await callRydrBackendAdmin(`/rides/internal/${encodeURIComponent(params.id)}/payment-resolution`, session.uid, {
      action,
      reason,
      requestId: crypto.randomUUID()
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Payment resolution failed" }, { status: 409 });
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: action === "write_off" ? "Payment Written Off" : "Payment Failure Resolved",
    targetType: "payment",
    targetId: params.id,
    reason
  });

  return NextResponse.json(result);
}
