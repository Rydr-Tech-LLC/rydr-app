import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { currentWorkspace } from "@/lib/workspace";
import { finishMetaLogin, metaSettings, metaStatus, recordMetaWebhook, startMetaLogin } from "@/lib/metaConnection";
import { constantEqual, validMetaSignature } from "@/lib/metaSecurity";

export const runtime = "nodejs";
type Context = { params: Promise<{ workspace: string; action: string }> };
const json = (body: object, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } });
async function routeContext(context: Context) {
  const params = await context.params;
  if (!["test", "live-beta"].includes(params.workspace) || params.workspace !== await currentWorkspace()) throw new Error("Invalid workspace");
  return params;
}
export async function GET(request: NextRequest, context: Context) {
  const { workspace, action } = await routeContext(context);
  if (action === "webhook") {
    const query = request.nextUrl.searchParams, secret = process.env.META_WEBHOOK_VERIFY_TOKEN;
    if (!secret) return json({ error: "Webhook setup incomplete" }, 503);
    if (query.get("hub.mode") !== "subscribe" || !constantEqual(query.get("hub.verify_token") ?? "", secret) || !query.has("hub.challenge")) return json({ error: "Invalid verification" }, 403);
    return new NextResponse(query.get("hub.challenge"), { headers: { "Content-Type": "text/plain", "Cache-Control": "no-store" } });
  }
  const actor = await getAdminSession();
  if (!actor) return json({ error: "Sign in to Mission Control as an administrator." }, 401);
  if (action === "status") return json(await metaStatus());
  if (action !== "callback") return json({ error: "Not found" }, 404);
  const cookieName = `__Host-rydr-meta-${workspace}`;
  try {
    if (request.nextUrl.searchParams.has("error")) throw new Error("Meta authorization was cancelled. You can start again from Social connections.");
    await finishMetaLogin(actor.uid, request.nextUrl.searchParams.get("state") ?? "", request.cookies.get(cookieName)?.value ?? "", request.nextUrl.searchParams.get("code") ?? "");
    const response = NextResponse.redirect(new URL(`/workspaces/${workspace}/campus-growth/social?connected=1`, metaSettings().origin));
    response.cookies.set(cookieName, "", { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 0 });
    response.headers.set("Cache-Control", "no-store"); response.headers.set("Referrer-Policy", "no-referrer");
    return response;
  } catch (error) {
    // No provider payload, token or authorization code is included in the error response.
    const response = json({ error: error instanceof Error && /^(Meta authorization|Login expired|Invalid Meta|Meta token exchange|Select Rydr|Meta could not|Configure |META_TOKEN|META_PUBLIC|Invalid Meta API)/.test(error.message) ? error.message : "Connection failed. Restart from Social connections in Mission Control." }, 400);
    response.cookies.set(cookieName, "", { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 0 });
    return response;
  }
}
export async function POST(request: NextRequest, context: Context) {
  const { workspace, action } = await routeContext(context);
  if (action === "webhook") {
    const secret = process.env.META_APP_SECRET;
    if (!secret) return json({ error: "Webhook setup incomplete" }, 503);
    if (Number(request.headers.get("content-length")) > 1000000) return json({ error: "Payload too large" }, 413);
    const body = await request.text();
    if (Buffer.byteLength(body) > 1000000) return json({ error: "Payload too large" }, 413);
    if (!validMetaSignature(body, request.headers.get("x-hub-signature-256") ?? "", secret)) return json({ error: "Invalid signature" }, 401);
    try { const payload = JSON.parse(body); await recordMetaWebhook(payload);
      const { ingestSocialWebhook } = await import('@/lib/socialAgent');
      await ingestSocialWebhook(payload); return json({ ok: true }); }
    catch { return json({ error: "Webhook could not be processed" }, 503); }
  }
  if (action !== "connect") return json({ error: "Not found" }, 404);
  const actor = await getAdminSession();
  if (!actor) return json({ error: "An administrator must connect Meta." }, 401);
  try {
    const settings = metaSettings();
    if (request.headers.get("origin") !== settings.origin) return json({ error: "Invalid request origin" }, 403);
    const login = await startMetaLogin(actor.uid);
    const response = json({ url: login.url });
    response.cookies.set(`__Host-rydr-meta-${workspace}`, login.state, { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 600 });
    return response;
  } catch { return json({ error: "Meta connection setup is incomplete. Check the server configuration." }, 503); }
}
