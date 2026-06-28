import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

type Action = "resolve" | "write_off";

// Manual ops-side outcomes for a ride whose Stripe charge failed and where
// the in-app Retry / Update Card flow isn't going to resolve it (rider
// already paid another way, fare is being written off as a goodwill
// gesture, etc.). This never calls Stripe directly — it only updates our
// own ledger state — so it can't accidentally trigger a duplicate charge or
// refund. Real money movement (refunds) still goes through stripe-backend's
// existing webhook-driven flows.
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { action, reason } = (await request.json()) as { action: Action; reason?: string };
  if (!["resolve", "write_off"].includes(action)) {
    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }

  const rideRef = adminDb.collection("rides").doc(params.id);
  const rideSnap = await rideRef.get();
  if (!rideSnap.exists) return NextResponse.json({ error: "Ride not found" }, { status: 404 });

  const update: Record<string, unknown> = {
    adminResolutionNote: reason ?? null,
    adminResolvedBy: session.uid,
    adminResolvedAt: FieldValue.serverTimestamp()
  };

  if (action === "write_off") {
    update.paymentStatus = "refunded";
  } else {
    // "resolve" — clears the failure off the queue without claiming Stripe
    // ever actually charged the card (e.g. the rider paid by another means).
    update.paymentStatus = "refunded";
    update.adminResolutionType = "manual_resolution";
  }

  await rideRef.set(update, { merge: true });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: action === "write_off" ? "Payment Written Off" : "Payment Failure Resolved",
    targetType: "payment",
    targetId: params.id,
    reason
  });

  return NextResponse.json({ ok: true });
}
