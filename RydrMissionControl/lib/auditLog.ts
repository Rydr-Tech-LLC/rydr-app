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
 */
export async function writeAuditLog(entry: Omit<AuditLogEntry, "createdAt">) {
  await adminDb.collection("audits").add({
    ...entry,
    createdAt: FieldValue.serverTimestamp()
  });
}
