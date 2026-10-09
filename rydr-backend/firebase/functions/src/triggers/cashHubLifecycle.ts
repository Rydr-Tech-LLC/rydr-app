import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { db, FieldValue, Timestamp } from "../admin";
import { sendPushToUser } from "../services/notificationSender";

const ACTIVE_REQUEST_STATUSES = new Set(["open", "connected"]);
const REVIEW_THRESHOLD_DEFAULT = 3;

export const expireCashHubRequests = onSchedule(
  { schedule: "every 15 minutes", timeZone: "America/New_York", retryCount: 3 },
  async () => {
    const now = Timestamp.now();
    const snapshot = await db.collection("cashRydrRequests")
      .where("expiresAt", "<=", now)
      .limit(200)
      .get();

    for (const requestSnap of snapshot.docs) {
      const expired = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(requestSnap.ref);
        if (!fresh.exists) return false;
        const request = fresh.data() ?? {};
        const expiresAt = request.expiresAt as { toMillis: () => number } | undefined;
        if (!ACTIVE_REQUEST_STATUSES.has(String(request.status ?? "")) || !expiresAt || expiresAt.toMillis() > now.toMillis()) return false;
        tx.set(requestSnap.ref, {
          status: "expired",
          terminalReason: "cash_hub_listing_expired",
          expiredAt: now,
          updatedAt: now,
          stateOwner: "firebase_function"
        }, { merge: true });
        return true;
      });
      if (!expired) continue;

      const conversations = await db.collection("cashHubConversations")
        .where("requestId", "==", requestSnap.id)
        .limit(100)
        .get();
      if (!conversations.empty) {
        const batch = db.batch();
        let writeCount = 0;
        conversations.docs.forEach((conversation) => {
          const status = String(conversation.data().status ?? "");
          if (!["cancelled", "completed", "declined", "released", "removed", "expired"].includes(status)) {
            batch.set(conversation.ref, { status: "expired", offerStatus: "expired", closedAt: now, updatedAt: now }, { merge: true });
            writeCount += 1;
          }
        });
        if (writeCount > 0) await batch.commit();
      }
    }
  }
);

export const onCashHubLateReleaseCreated = onDocumentCreated(
  "cashHubLateReleaseMarkers/{markerId}",
  async (event) => {
    const markerRef = event.data?.ref;
    const marker = event.data?.data();
    const driverId = String(marker?.driverId ?? "");
    if (!markerRef || !driverId) return;
    const driverRef = db.collection("drivers").doc(driverId);
    const configRef = db.collection("platformConfig").doc("cashRydrHub");

    const result = await db.runTransaction(async (tx) => {
      const [freshMarker, driverSnap, configSnap] = await Promise.all([
        tx.get(markerRef), tx.get(driverRef), tx.get(configRef)
      ]);
      if (!freshMarker.exists || freshMarker.data()?.processedAt || !driverSnap.exists) return null;
      const driver = driverSnap.data() ?? {};
      const config = configSnap.exists ? configSnap.data() ?? {} : {};
      const threshold = Math.max(1, Number(config.cashHubLateReleaseReviewThreshold) || REVIEW_THRESHOLD_DEFAULT);
      const count = Math.max(0, Number(driver.cashHubLateReleaseCount) || 0) + 1;
      const requiresReview = count >= threshold;
      tx.set(driverRef, {
        cashHubLateReleaseCount: count,
        cashHubPenaltyCount: FieldValue.increment(1),
        cashHubLastLateReleaseAt: FieldValue.serverTimestamp(),
        cashHubLastLateReleaseRequestId: marker?.requestId ?? null,
        cashHubWarnings: FieldValue.arrayUnion(`Late release ${count}: ${marker?.requestId ?? event.params.markerId}`),
        ...(requiresReview ? {
          cashHubAccessStatus: "review_required",
          cashHubAccessSuspendedAt: FieldValue.serverTimestamp(),
          cashHubAccessReviewReason: `Reached ${count} late releases.`
        } : {}),
        updatedAt: FieldValue.serverTimestamp()
      }, { merge: true });
      tx.set(markerRef, {
        status: requiresReview ? "review_required" : "processed",
        penaltyNumber: count,
        reviewThreshold: threshold,
        processedAt: FieldValue.serverTimestamp()
      }, { merge: true });
      return { count, requiresReview };
    });

    if (!result) return;
    await sendPushToUser({
      audience: "driver",
      uid: driverId,
      title: result.requiresReview ? "CashRydr Hub access paused" : "CashRydr Hub late-release warning",
      body: result.requiresReview
        ? "Your access is paused for review after repeated late releases."
        : `Late release ${result.count} was added to your CashRydr Hub record.`,
      route: { type: "cashHubUpdate", target: "cashHub", requestId: String(marker?.requestId ?? "") || undefined }
    });
  }
);
