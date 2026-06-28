import { randomUUID } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { cleanupStripeAccount } from "@/lib/stripeCleanup";

// Admin-initiated HARD delete of a driver — distinct from the account
// deletion request queue (/account-deletions), which anonymizes a profile
// in place so historical ride/ledger rows keep a valid reference. This
// route is for drivers an admin wants to remove outright with no request
// from the driver involved (e.g. spam/duplicate signups, fraud caught
// during verification, a test account) — it deletes the Firebase Auth
// user, the entire drivers/{uid} Firestore doc (and its notificationTokens
// subcollection), and runs the same Stripe cleanup used by account
// deletion. It does not touch the request-queue flow or its records.
//
// Deliberately does not delete Storage files: license/registration/
// insurance images are driver-specific, but vehicle imagery is sourced
// from the shared vehicleLibrary collection and must not be touched here.
//
// Irreversible. Any ride/ledger rows referencing this uid will be left
// pointing at a uid that no longer resolves to a driver record — that
// tradeoff is intentional for this action and is why it's separate from
// the anonymize-based account deletion flow.
export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { reason } = (await request.json().catch(() => ({}))) as { reason?: string };

  const driverRef = adminDb.collection("drivers").doc(params.uid);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) return NextResponse.json({ error: "Driver not found" }, { status: 404 });
  const profile = driverSnap.data() as Record<string, unknown>;

  try {
    const stripeResult = await cleanupStripeAccount("driver", profile, session.uid, randomUUID(), params.uid);

    await adminAuth.deleteUser(params.uid).catch((err: { code?: string }) => {
      if (err?.code !== "auth/user-not-found") throw err;
    });

    const tokensSnap = await driverRef.collection("notificationTokens").get();
    const batch = adminDb.batch();
    tokensSnap.docs.forEach((doc) => batch.delete(doc.ref));
    if (!tokensSnap.empty) await batch.commit();

    await driverRef.delete();

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Driver Deleted (Hard Delete)",
      targetType: "driver",
      targetId: params.uid,
      reason
    });

    return NextResponse.json({ ok: true, stripe: stripeResult });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
