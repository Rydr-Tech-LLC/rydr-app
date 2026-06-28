// Shared helper for telling stripe-backend to deactivate/clean up a user's
// Stripe records (Customer + Connect account) from an admin-initiated flow.
// Used by both the account-deletion request queue (anonymize) and the
// driver hard-delete action (full removal) — same Stripe-side cleanup
// either way, only what happens to the Firestore/Auth record afterward
// differs between the two callers.
export async function cleanupStripeAccount(
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
