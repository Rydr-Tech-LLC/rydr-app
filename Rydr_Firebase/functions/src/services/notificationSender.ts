// Push notification sender service — the single place every Cloud Function
// trigger goes through to deliver a push notification to a rider or driver.
//
// Token storage schema (must match Core/NotificationManager.swift and
// RydrDriver/RydrDriver/Core/DriverNotificationManager.swift exactly):
//   riders/{uid}/notificationTokens/{token}   { fcmToken, enabled, ... }
//   drivers/{uid}/notificationTokens/{token}  { fcmToken, enabled, ... }
//
// The `userInfo`/data payload keys (`type`, `target`, `rideId`, `requestId`,
// `chatId`) must match `NotificationRoute`/`DriverNotificationRoute` on the
// client, which parse exactly those keys out of the notification's data
// payload to route a tap to the right screen.

import type * as admin from "firebase-admin";
import { db, FieldValue, messaging } from "../admin";

export type NotificationAudience = "rider" | "driver";

/** Matches NotificationRoute/DriverNotificationRoute's `type` field on the client. */
export type NotificationType =
  | "rideAccepted"
  | "driverArrived"
  | "rideStarted"
  | "rideCompleted"
  | "rideCancelled"
  | "paymentFailed"
  | "paymentPending"
  | "supportReply"
  | "driverApprovalDecision"
  | "rydrBankCode"
  | "rydrBankCompleted"
  | "betaAnnouncement"
  | "promo";

export interface NotificationRouteData {
  type: NotificationType;
  target: string;
  rideId?: string;
  requestId?: string;
  chatId?: string;
}

export interface SendPushArgs {
  audience: NotificationAudience;
  uid: string;
  title: string;
  body: string;
  route: NotificationRouteData;
}

function collectionFor(audience: NotificationAudience): string {
  return audience === "rider" ? "riders" : "drivers";
}

/** All non-`type`/`target`/`rideId`/`requestId`/`chatId` keys must be strings —
 * FCM data payloads are string-only on the wire. */
function dataPayload(route: NotificationRouteData): Record<string, string> {
  const data: Record<string, string> = {
    type: route.type,
    target: route.target
  };
  if (route.rideId) data.rideId = route.rideId;
  if (route.requestId) data.requestId = route.requestId;
  if (route.chatId) data.chatId = route.chatId;
  return data;
}

async function writeInboxRecord(args: SendPushArgs): Promise<void> {
  const { audience, uid, title, body, route } = args;
  await db
    .collection(collectionFor(audience))
    .doc(uid)
    .collection("notifications")
    .add({
      title,
      body,
      type: route.type,
      target: route.target,
      rideId: route.rideId ?? null,
      requestId: route.requestId ?? null,
      chatId: route.chatId ?? null,
      isRead: false,
      createdAt: FieldValue.serverTimestamp()
    });
}

/**
 * Sends a push notification to every enabled device token registered for
 * the given rider/driver, and prunes any token FCM reports as
 * unregistered/invalid so dead tokens don't accumulate forever.
 *
 * Never throws — a notification failure must never fail the Firestore
 * write/trigger that caused it. Errors are logged and swallowed.
 */
export async function sendPushToUser(args: SendPushArgs): Promise<void> {
  const { audience, uid, title, body, route } = args;

  try {
    await writeInboxRecord(args);

    const tokensSnap = await db
      .collection(collectionFor(audience))
      .doc(uid)
      .collection("notificationTokens")
      .where("enabled", "==", true)
      .get();

    if (tokensSnap.empty) {
      console.log(`[notificationSender] no enabled tokens for ${audience}/${uid} (${route.type})`);
      return;
    }

    const tokens = tokensSnap.docs
      .map((doc) => doc.data().fcmToken as string | undefined)
      .filter((token): token is string => Boolean(token));

    if (tokens.length === 0) return;

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: { title, body },
      data: dataPayload(route),
      apns: {
        payload: {
          aps: { sound: "default", badge: 1 }
        }
      },
      android: {
        priority: "high"
      }
    };

    const response = await messaging.sendEachForMulticast(message);

    const staleTokenDocs: FirebaseFirestore.DocumentReference[] = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error?.code;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        staleTokenDocs.push(tokensSnap.docs[index].ref);
      } else {
        console.warn(`[notificationSender] send failed for ${audience}/${uid}:`, code, result.error?.message);
      }
    });

    if (staleTokenDocs.length > 0) {
      const batch = db.batch();
      staleTokenDocs.forEach((ref) => batch.delete(ref));
      await batch.commit();
      console.log(`[notificationSender] pruned ${staleTokenDocs.length} stale token(s) for ${audience}/${uid}`);
    }

    console.log(
      `[notificationSender] sent ${route.type} to ${audience}/${uid}: ${response.successCount}/${tokens.length} succeeded`
    );
  } catch (err) {
    console.error(`[notificationSender] unexpected failure sending ${route.type} to ${audience}/${uid}`, err);
  }
}
