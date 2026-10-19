import "server-only";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { getControlDb } from "./firebaseAdmin";

export const CAMPAIGNS = "notificationCampaigns";
export const betaSchedule = [
  { key: "five-days", at: "2026-10-27T13:00:00Z", title: "Live Beta starts in 5 days", rider: "Rydr Live Beta starts November 1 at 9 AM Eastern. Get ready to help shape a new way to rideshare!", driver: "Rydr Live Beta starts November 1 at 9 AM Eastern. Get ready to drive and help shape a new way to rideshare!" },
  { key: "three-days", at: "2026-10-29T13:00:00Z", title: "Get ready: Live Beta in 3 days", rider: "We're almost ready! Rydr Live Beta starts November 1 at 9 AM Eastern. Take real rides and share your feedback.", driver: "We're almost ready! Rydr Live Beta starts November 1 at 9 AM Eastern. Check your driver setup and get ready to go online." },
  { key: "launch", at: "2026-11-01T14:00:00Z", title: "Rydr Live Beta is now live!", rider: "Take your first ride today! Share your feedback and help shape Rydr. Limited beta service is available.", driver: "Go online and take your first beta trip today! Share your feedback and help shape Rydr. Limited beta service is available." }
] as const;

export async function seedBetaSchedule(uid: string) {
  const adminDb = getControlDb();
  await adminDb.runTransaction(async tx => {
    const rows = betaSchedule.flatMap(item => (["rider", "driver"] as const).map(audience => ({
      id: `live-beta-2026-${item.key}-${audience}`, audience, item
    })));
    const snapshots = await Promise.all(rows.map(row => tx.get(adminDb.collection(CAMPAIGNS).doc(row.id))));
    rows.forEach((row, i) => {
      if (!snapshots[i].exists) tx.create(snapshots[i].ref, {
        audience: row.audience, title: row.item.title, body: row.item[row.audience],
        sendAt: Timestamp.fromDate(new Date(row.item.at)), status: "scheduled", cursor: null,
        createdBy: uid, createdAt: FieldValue.serverTimestamp(), counts: {}
      });
    });
  });
}

export function validateAnnouncement(body: unknown) {
  const value = body as Record<string, unknown> | null;
  if (!value || !["rider", "driver"].includes(String(value.audience))) throw new Error("Choose riders or drivers.");
  const title = typeof value.title === "string" ? value.title.trim() : "";
  const message = typeof value.body === "string" ? value.body.trim() : "";
  const immediate = value.action === "sendNow";
  const date = immediate ? new Date() : typeof value.sendAt === "string" && /(?:Z|[+-]\d{2}:\d{2})$/.test(value.sendAt) ? new Date(value.sendAt) : new Date(NaN);
  if (!title || title.length > 100 || !message || message.length > 500) throw new Error("Enter a title (up to 100 characters) and message (up to 500).");
  if (!Number.isFinite(date.getTime()) || (!immediate && date.getTime() < Date.now() + 60_000)) throw new Error("Choose a send time at least one minute in the future, with an explicit timezone.");
  return { audience: value.audience as "rider" | "driver", title, body: message, sendAt: Timestamp.fromDate(date) };
}
