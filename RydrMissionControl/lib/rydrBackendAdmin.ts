import "server-only";

export async function callRydrBackendAdmin(
  path: string,
  adminUid: string,
  body: Record<string, unknown>
) {
  const base = process.env.RYDR_BACKEND_BASE_URL;
  const token = process.env.RYDR_INTERNAL_SERVICE_TOKEN;
  if (!base || !token) throw new Error("Rydr backend admin integration is not configured");
  const response = await fetch(`${base.replace(/\/+$/, "")}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-rydr-internal-token": token
    },
    body: JSON.stringify({ ...body, adminUid })
  });
  const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    throw new Error(typeof payload.error === "string" ? payload.error : `Rydr backend request failed (${response.status})`);
  }
  return payload;
}
