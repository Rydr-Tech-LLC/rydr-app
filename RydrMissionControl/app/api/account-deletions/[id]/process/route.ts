import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import type { AccountDeletionRequestRecord } from "@/lib/types";

type Action = "complete" | "reject";

// Anonymizes (rather than hard-deletes) the Firestore profile doc so ride
// history / ledger rows that reference this uid don't end up with dangling
// references, while removing every direct identifier — this matches the
// GDPR-safe "anonymize, don't orphan" approach called for in Part 11 of the
// beta hardening spec.
function anonymizedFields(role: "rider" | "driver") {
  const common = {
    firstName: "Deleted",
    lastName: "User",
    email: null,
    phoneNumber: null,
    phoneE164: null,
    deletedAt: FieldValue.serverTimestamp(),
    accountStatus: "removed"
  };
  if (role === "driver") {
    return {
      ...common,
      license: null,
      address: null,
      stripeAccountId: null,
      driverApprovalStatus: "rejected",
      isApproved: false
    };
  }
  return common;
}

async function cleanupStripe(
  role: "rider" | "driver",
  profile: Record<string, unknown>,
  adminUid: string,
  requestId: string,
  uid: string
) {
  const base = process.env.STRIPE_BACKEND_BASE_URL;
  const secret = process.env.RYDR_INTERNAL_ADMIN_SECRET;
  if (!base || !secret) {
    // Not configured — surface this clearly in the audit trail rather than
    // silently skipping Stripe cleanup. Firestore/Auth deletion still
    // proceeds; an admin can re-run cleanup once env vars are set.
    return { skipped: true, reason: "STRIPE_BACKEND_BASE_URL or RYDR_INTERNAL_ADMIN_SECRET not configured" };
  }

  const res = await fetch(`${base.replace(/\/+$/, "")}/admin/cleanup-account`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-internal-admin-secret": secret,
      "x-admin-uid": adminUid
    },
    body: JSON.stringify({
      role,
      requestId,
      uid,
      stripeCustomerId: profile.stripeCustomerId ?? null,
      stripeAccountId: profile.stripeAccountId ?? null
    })
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(`stripe cleanup failed: ${body.error || res.status}`);
  }
  return res.json();
}

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { action, reason } = (await request.json()) as { action: Action; reason?: string };
  if (!["complete", "reject"].includes(action)) {
    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }

  const requestRef = adminDb.collection("accountDeletionRequests").doc(params.id);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) return NextResponse.json({ error: "Request not found" }, { status: 404 });
  const deletionRequest = requestSnap.data() as AccountDeletionRequestRecord;
  const uid = deletionRequest.uid;
  const role = deletionRequest.role === "driver" ? "driver" : "rider";

  if (action === "reject") {
    await requestRef.set(
      { status: "rejected", rejectionReason: reason ?? null, processedAt: FieldValue.serverTimestamp(), processedBy: session.uid },
      { merge: true }
    );
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Account Deletion Rejected",
      targetType: "accountDeletion",
      targetId: params.id,
      reason
    });
    return NextResponse.json({ ok: true });
  }

  // action === "complete"
  await requestRef.set({ status: "processing", processedBy: session.uid }, { merge: true });

  try {
    const profileRef = adminDb.collection(role === "driver" ? "drivers" : "riders").doc(uid);
    const profileSnap = await profileRef.get();
    const profile = profileSnap.exists ? (profileSnap.data() as Record<string, unknown>) : {};

    const stripeResult = await cleanupStripe(role, profile, session.uid, params.id, uid);

    // Remove the Firebase Auth account so the person can no longer sign in,
    // then anonymize (not delete) the Firestore profile so historical ride
    // / ledger records stay internally consistent.
    await adminAuth.deleteUser(uid).catch((err: { code?: string }) => {
      if (err?.code !== "auth/user-not-found") throw err;
    });
    if (profileSnap.exists) {
      await profileRef.set(anonymizedFields(role), { merge: true });
    }

    // Disable any lingering push notification tokens rather than leaving
    // them to error out silently against a deleted account.
    const tokensSnap = await profileRef.collection("notificationTokens").get();
    await Promise.all(tokensSnap.docs.map((doc) => doc.ref.set({ enabled: false }, { merge: true })));

    await requestRef.set(
      { status: "completed", processedAt: FieldValue.serverTimestamp(), processedBy: session.uid },
      { merge: true }
    );

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Account Deletion Completed",
      targetType: "accountDeletion",
      targetId: params.id,
      reason: stripeResult && (stripeResult as { skipped?: boolean }).skipped ? "Stripe cleanup skipped — see logs" : undefined
    });

    return NextResponse.json({ ok: true, stripe: stripeResult });
  } catch (err) {
    // Roll the request back to "requested" so it stays in the queue for a
    // retry rather than silently disappearing mid-failure.
    await requestRef.set({ status: "requested" }, { merge: true });
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
