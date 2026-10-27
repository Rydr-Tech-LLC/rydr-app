import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

export const metaHash = (value: string) => createHash("sha256").update(value).digest("hex");
export function constantEqual(a: string, b: string) {
  return Boolean(a && b && Buffer.byteLength(a) === Buffer.byteLength(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b)));
}
export function validMetaSignature(body: string, signature: string, secret: string) {
  return Boolean(secret && /^sha256=[a-f0-9]{64}$/.test(signature) && constantEqual(signature, `sha256=${createHmac("sha256", secret).update(body).digest("hex")}`));
}
export function metaKey(value: string) {
  if (!/^[a-f0-9]{64}$/i.test(value)) throw new Error("META_TOKEN_ENCRYPTION_KEY must contain 32 random bytes encoded as hex.");
  return Buffer.from(value, "hex");
}
export function encryptMetaToken(token: string, key: string, context: string) {
  const iv = randomBytes(12), cipher = createCipheriv("aes-256-gcm", metaKey(key), iv);
  cipher.setAAD(Buffer.from(context));
  const encrypted = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), encrypted].map(x => x.toString("base64url")).join(".");
}
export function decryptMetaToken(value: string, key: string, context: string) {
  const [iv, tag, body] = value.split(".").map(x => Buffer.from(x, "base64url"));
  const cipher = createDecipheriv("aes-256-gcm", metaKey(key), iv);
  cipher.setAAD(Buffer.from(context)); cipher.setAuthTag(tag);
  return Buffer.concat([cipher.update(body), cipher.final()]).toString("utf8");
}
export function metaOrigin(value: string) {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.pathname !== "/" || url.search || url.hash) throw new Error("META_PUBLIC_ORIGIN must be an HTTPS origin.");
  return url.origin;
}
export function validMetaState(saved: { uid?: string; expiresAt?: number; used?: boolean } | undefined, uid: string, state: string, cookie: string, now = Date.now()) {
  return Boolean(/^[a-f0-9]{64}$/.test(state) && constantEqual(state, cookie) && saved?.uid === uid && !saved.used && (saved.expiresAt ?? 0) > now);
}
