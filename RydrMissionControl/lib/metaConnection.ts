import "server-only";
import { createHmac, randomBytes } from "node:crypto";
import { getWorkspaceDb } from "./firebaseAdmin";
import { currentWorkspace } from "./workspace";
import { encryptMetaToken, metaHash, metaKey, metaOrigin, validMetaState } from "./metaSecurity";

export function metaSettings() {
  const required = ["META_APP_SECRET", "META_TOKEN_ENCRYPTION_KEY", "META_WEBHOOK_VERIFY_TOKEN", "META_PUBLIC_ORIGIN"];
  const missing = required.filter(name => !process.env[name]);
  if (missing.length) throw new Error(`Configure ${missing.join(", ")} before connecting Meta.`);
  metaKey(process.env.META_TOKEN_ENCRYPTION_KEY!);
  const version = process.env.META_GRAPH_VERSION || "v26.0";
  if (!/^v\d+\.0$/.test(version)) throw new Error("Invalid Meta API version.");
  return { appId: process.env.META_APP_ID || "1747510056547573", configId: process.env.META_LOGIN_CONFIG_ID || "1117275767350738",
    origin: metaOrigin(process.env.META_PUBLIC_ORIGIN!), secret: process.env.META_APP_SECRET!, key: process.env.META_TOKEN_ENCRYPTION_KEY!, version };
}
export async function metaStatus() {
  const db = await getWorkspaceDb();
  const record = (await db.collection("metaConnections").doc("rydr").get()).data();
  let setupError = "";
  try { metaSettings(); } catch (error) { setupError = (error as Error).message; }
  // Never return tokens or state records to the browser.
  return { configured: !setupError, setupError, connected: Boolean(record?.tokenEncrypted), pageId: record?.pageId ?? null,
    pageName: record?.pageName ?? null, instagramUsername: record?.instagramUsername ?? null,
    connectedAt: record?.connectedAt ?? null, expiresAt: record?.expiresAt ?? null, lastWebhookAt: record?.lastWebhookAt ?? null,
    expired: Boolean(record?.expiresAt && record.expiresAt <= Date.now()), origin: process.env.META_PUBLIC_ORIGIN ?? "https://rydr-app-missioncontrol.vercel.app" };
}
export async function startMetaLogin(uid: string) {
  const settings = metaSettings(), workspace = await currentWorkspace(), db = await getWorkspaceDb();
  const state = randomBytes(32).toString("hex");
  await db.collection("metaOAuthStates").doc(metaHash(state)).set({ uid, expiresAt: Date.now() + 600000, used: false });
  const url = new URL(`https://www.facebook.com/${settings.version}/dialog/oauth`);
  url.search = new URLSearchParams({ client_id: settings.appId, config_id: settings.configId,
    redirect_uri: `${settings.origin}/api/meta/${workspace}/callback`, state, response_type: "code", override_default_response_type: "true" }).toString();
  return { state, url: url.toString() };
}

async function graph(path: string, token: string, params: Record<string, string> = {}) {
  const settings = metaSettings();
  const url = new URL(`https://graph.facebook.com/${settings.version}/${path}`);
  url.search = new URLSearchParams({ ...params, appsecret_proof: createHmac("sha256", settings.secret).update(token).digest("hex") }).toString();
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, cache: "no-store", signal: AbortSignal.timeout(20000) });
  const json = await response.json();
  if (!response.ok || json.error) throw new Error("Meta could not validate the selected business assets. Check app permissions and account access.");
  return json;
}

export async function finishMetaLogin(uid: string, state: string, cookie: string, code: string) {
  const settings = metaSettings(), workspace = await currentWorkspace(), db = await getWorkspaceDb();
  if (!/^[a-f0-9]{64}$/.test(state) || !code || code.length > 8192) throw new Error("Invalid Meta callback.");
  const ref = db.collection("metaOAuthStates").doc(metaHash(state));
  await db.runTransaction(async tx => {
    const saved = (await tx.get(ref)).data();
    if (!validMetaState(saved, uid, state, cookie)) throw new Error("Login expired or could not be verified. Start the connection again.");
    tx.update(ref, { used: true });
  });
  const exchange = new URL(`https://graph.facebook.com/${settings.version}/oauth/access_token`);
  exchange.search = new URLSearchParams({ client_id: settings.appId, client_secret: settings.secret, code,
    redirect_uri: `${settings.origin}/api/meta/${workspace}/callback` }).toString();
  // Token exchange happens only server-to-server; never log the URL or provider response.
  const response = await fetch(exchange, { cache: "no-store", signal: AbortSignal.timeout(20000) });
  const token = await response.json();
  if (!response.ok || typeof token.access_token !== "string") throw new Error("Meta token exchange failed. Start the connection again.");
  type Page = { id: string; name: string; access_token?: string; instagram_business_account?: { id: string; username: string } };
  const pages: Page[] = [];
  let after: string | undefined;
  for (let i = 0; i < 10; i++) {
    const result = await graph("me/accounts", token.access_token, { fields: "id,name,access_token,instagram_business_account{id,username}", limit: "100", ...(after ? { after } : {}) });
    if (!Array.isArray(result.data)) throw new Error("Meta returned no Page list.");
    pages.push(...result.data);
    after = result.paging?.next ? result.paging?.cursors?.after : undefined;
    if (!after) break;
  }
  const expectedPage = process.env.META_FACEBOOK_PAGE_ID || "1444445918742638";
  const expectedInstagram = (process.env.META_INSTAGRAM_USERNAME || "rydr_tech").toLowerCase();
  const page = pages.find(p => p.id === expectedPage && p.instagram_business_account?.username?.toLowerCase() === expectedInstagram);
  if (!page?.access_token || !page.instagram_business_account) throw new Error("Select Rydr Tech's business Facebook Page linked to @rydr_tech. No other account has been saved.");
  const expiry = Number(token.expires_in);
  await db.collection("metaConnections").doc("rydr").set({ pageId: page.id, pageName: page.name,
    instagramId: page.instagram_business_account.id, instagramUsername: page.instagram_business_account.username,
    tokenEncrypted: encryptMetaToken(page.access_token, settings.key, `${workspace}:${page.id}`),
    connectedAt: Date.now(), connectedBy: uid, expiresAt: Number.isFinite(expiry) && expiry > 0 ? Date.now() + expiry * 1000 : null,
    lastWebhookAt: null, status: "connected" });
}

export async function recordMetaWebhook(payload: { object?: unknown; entry?: unknown }) {
  if (!["page", "instagram"].includes(String(payload.object)) || !Array.isArray(payload.entry)) return;
  const db = await getWorkspaceDb(), ref = db.collection("metaConnections").doc("rydr");
  const connection = (await ref.get()).data();
  if (!connection) return;
  // Connection health only. Do not store unrelated messages or trigger automated replies.
  const matched = payload.entry.some((entry: { id?: unknown }) => entry && [connection.pageId, connection.instagramId].includes(String(entry.id)));
  if (matched) await ref.update({ lastWebhookAt: Date.now() });
}
