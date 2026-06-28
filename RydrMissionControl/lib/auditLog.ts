import "server-only";
import { FieldValue } from "firebase-admin/firestore";
import { adminDb } from "./firebaseAdmin";
import type { AuditLogEntry } from "./types";

/**
 * Every privileged action funnels through here. Writes to /audits, which
 * the live Firestore rules already lock to `allow read, write: if false`
 * for clients — only the Admin SDK (this server) can ever touch it, so
 * the trail can't be edited or deleted by anyone going through the apps
 * or a compromised client session.
 *
 * Many callers pass through an optional `reason` (and similar fields)
 * straight from a request body, which is `undefined` whenever the admin
 * leaves the reason textarea empty. The Firestore Admin SDK rejects
 * explicit `undefined` values in a document by default, so we strip any
 * undefined-valued keys here once, centrally — every current and future
 * call site is protected without each one having to remember to do it.
 */
export async function writeAuditLog(entry: Omit<AuditLogEntry, "createdAt">) {
  const sanitized = Object.fromEntries(
    Object.entries(entry).filter(([, value]) => value !== undefined)
  );
  await adminDb.collection("audits").add({
    ...sanitized,
    createdAt: FieldValue.serverTimestamp()
  });
}
