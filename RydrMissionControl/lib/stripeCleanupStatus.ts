import { randomUUID } from "crypto";

export async function stripeCleanupStatus(adminUid: string) {
  const base = process.env.STRIPE_BACKEND_BASE_URL?.trim();
  const secret = process.env.RYDR_INTERNAL_ADMIN_SECRET;
  if (!base || !secret) return { configured: false, reason: "missing_configuration", baseConfigured: Boolean(base), secretConfigured: Boolean(secret) };
  const root = base.replace(/\/+$/, "").replace(/\/workspaces\/(test|live-beta)$/, "");
  const workspaces = await Promise.all((["test", "live-beta"] as const).map(async workspace => {
    try {
      // Authentication runs before role validation. An intentionally invalid role
      // proves server-to-server authentication without reading or deleting a user.
      const response = await fetch(`${root}/workspaces/${workspace}/admin/cleanup-account`, {
        method: "POST", cache: "no-store", signal: AbortSignal.timeout(15000),
        headers: { "Content-Type": "application/json", "x-internal-admin-secret": secret, "x-admin-uid": adminUid },
        body: JSON.stringify({ role: "configuration_check", requestId: randomUUID() })
      });
      const body = await response.json().catch(() => ({}));
      return { workspace, authenticated: response.status === 400 && body.error === "invalid_account", status: response.status };
    } catch { return { workspace, authenticated: false, status: null }; }
  }));
  return { configured: workspaces.every(result => result.authenticated), baseConfigured: true, secretConfigured: true, workspaces };
}
