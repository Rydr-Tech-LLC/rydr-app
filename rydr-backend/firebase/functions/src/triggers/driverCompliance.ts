import { sendPushToUser, type NotificationType } from "../services/notificationSender";
import { onDocumentWritten } from "../workspaceFunctions";
import { onSchedule } from "../workspaceFunctions";
import { db } from "../admin";
import { reconcileDriverCompliance } from "../services/driverComplianceService";

async function reconcileAllDrivers() {
  const policy = (await db.collection("platformConfig").doc("driverCompliance").get()).data() ?? {};
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    let query = db.collection("drivers").orderBy("__name__").limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) return;
    for (const driver of page.docs) {
      await reconcileDriverCompliance(driver.id, policy);
      const pending = await driver.ref.collection("notifications").where("pushStatus", "in", ["pending", "retry_pending", "awaiting_device"]).limit(30).get();
      for (const notification of pending.docs) {
        const value = notification.data();
        if (!["driverDocumentReminder", "driverScreeningRequired"].includes(value.type)) continue;
        await sendPushToUser({ audience: "driver", uid: driver.id, notificationId: notification.id, title: value.title, body: value.body, route: { type: value.type as NotificationType, target: value.target } });
      }
    }
    cursor = page.docs[page.docs.length - 1];
  }
}
export const maintainDriverDocumentCompliance = onSchedule({ schedule: "0 * * * *", timeZone: "America/New_York", timeoutSeconds: 540 }, reconcileAllDrivers);
export const onDriverCompliancePolicyChanged = onDocumentWritten("platformConfig/driverCompliance", reconcileAllDrivers);
export const onDriverComplianceChanged = onDocumentWritten("drivers/{uid}", async event => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;
  const relevant = (data: any) => JSON.stringify([data?.documents, data?.backgroundScreening, data?.driverApprovalStatus, data?.accountStatus, data?.safetyHold, data?.safetyReviewStatus, data?.isApproved, ...Object.entries(data ?? {}).filter(([key]) => key.startsWith("documents."))]);
  if (relevant(before) === relevant(after)) return;
  await reconcileDriverCompliance(event.params.uid);
});
