import { randomUUID } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { cleanupStripeAccount } from "@/lib/stripeCleanup";

// Admin-initiated HARD delete of a rider — mirrors
// app/api/drivers/[uid]/delete exactly, distinct from the account deletion
// request queue (/account-deletions), which anonymizes a profile in place
// so historical ride/ledger rows keep a valid reference. This route is for
// riders an admin wants to remove outright with no request from the rider
// involved — it deletes the Firebase Auth user, the entire riders/{uid}
// Firestore doc (and its notificationTokens subcollection), and runs the
// same Stripe cleanup used by account deletion. It does not touch the
// request-queue flow or its records.
//
// Irreversible. Any ride/ledger rows referencing this uid will be left
// pointing at a uid that no longer resolves to a rider record — that
// tradeoff is intentional for this action and is why it's separate from
// the anonymize-based account deletion flow.
export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { reason } = (await request.json().catch(() => ({}))) as { reason?: string };

  const riderRef = adminDb.collection("riders").doc(params.uid);
  const riderSnap = await riderRef.get();
  if (!riderSnap.exists) return NextResponse.json({ error: "Rider not found" }, { status: 404 });
  const profile = riderSnap.data() as Record<string, unknown>;
  const phone = (profile.phoneE164 ?? profile.phoneNumber) as string | undefined;

  try {
    const stripeResult = await cleanupStripeAccount("rider", profile, session.uid, randomUUID(), params.uid);

    await adminAuth.deleteUser(params.uid).catch((err: { code?: string }) => {
      if (err?.code !== "auth/user-not-found") throw err;
    });

    const tokensSnap = await riderRef.collection("notificationTokens").get();
    const batch = adminDb.batch();
    let hasBatchDeletes = false;
    tokensSnap.docs.forEach((doc) => batch.delete(doc.ref));
    if (!tokensSnap.empty) hasBatchDeletes = true;
    if (phone) {
      const phoneIndexRef = adminDb.collection("riderPhoneIndex").doc(phone);
      const phoneIndexSnap = await phoneIndexRef.get();
      if (phoneIndexSnap.exists && phoneIndexSnap.data()?.uid === params.uid) {
        batch.delete(phoneIndexRef);
        hasBatchDeletes = true;
      }
    }
    if (hasBatchDeletes) await batch.commit();

    await riderRef.delete();

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Rider Deleted (Hard Delete)",
      targetType: "rider",
      targetId: params.uid,
      reason
    });

    return NextResponse.json({ ok: true, stripe: stripeResult });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
