import {currentWorkspace, workspaceServiceURL} from "@/lib/workspace";
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
  const mode = (await currentWorkspace()) === "test" ? "test" : "live";
  const scoped = (profile.stripeProfiles as Record<string, Record<string, unknown>> | undefined)?.[mode];
  const active = scoped ?? (profile.stripeMode === mode || (!profile.stripeMode && mode === "test") ? profile : {});
  const stripeCustomerId = typeof active.stripeCustomerId === "string" ? active.stripeCustomerId.trim() : "";
  const stripeAccountId = typeof active.stripeAccountId === "string" ? active.stripeAccountId.trim() : "";
  if (!stripeCustomerId && !stripeAccountId) {
    return { notRequired: true };
  }

  const base = process.env.STRIPE_BACKEND_BASE_URL;
  const secret = process.env.RYDR_INTERNAL_ADMIN_SECRET;
  if (!base || !secret) {
    // Never orphan a live Stripe Customer or Connect account by continuing
    // with Auth/Firestore deletion when the required cleanup path is absent.
    throw new Error("Stripe cleanup is not configured. Set STRIPE_BACKEND_BASE_URL and the matching RYDR_INTERNAL_ADMIN_SECRET in Mission Control and the Stripe backend, then redeploy.");
  }

  const res = await fetch(`${await workspaceServiceURL(base)}/admin/cleanup-account`, {
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
      stripeCustomerId: stripeCustomerId || null,
      stripeAccountId: stripeAccountId || null
    })
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(`stripe cleanup failed: ${body.detail || body.error || res.status}`);
  }
  return res.json();
}
