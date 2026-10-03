import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { db, FieldValue } from "../admin";
import { sendPushToUser } from "../services/notificationSender";

interface CashHubConversation {
  requestId?: string;
  riderUid?: string;
  driverUid?: string;
  driverName?: string;
  riderName?: string;
  status?: string;
  offerStatus?: string;
}

interface CashHubMessage {
  senderUid?: string;
  senderRole?: string;
  senderName?: string;
  kind?: string;
  recipientUid?: string;
}

interface CashHubRequest {
  riderUid?: string;
  connectedDriverUid?: string;
  connectedDriverName?: string;
  status?: string;
  driverQueueStatus?: string;
  visibility?: string;
  allowedDriverUids?: string[];
  eligibleDriverUids?: string[];
  tripFormat?: string;
}

export const onCashHubRequestCreated = onDocumentCreated("cashRydrRequests/{requestId}", async (event) => {
  const request = event.data?.data() as CashHubRequest | undefined;
  if (!request || request.status !== "open" || !request.riderUid) return;
  let driverIds: string[] = [];
  if (Array.isArray(request.eligibleDriverUids)) {
    driverIds = request.eligibleDriverUids.slice(0, 100);
  } else if (request.visibility === "Favorite Drivers") {
    driverIds = Array.isArray(request.allowedDriverUids) ? request.allowedDriverUids.slice(0, 10) : [];
  } else {
    // Legacy posts created before backend-owned audience selection.
    const drivers = await db.collection("cashHubDriverProfiles").where("cashHubAccessActive", "==", true).limit(100).get();
    driverIds = drivers.docs.map((doc) => doc.id);
  }
  await Promise.all(driverIds.map((uid) => sendPushToUser({
    audience: "driver",
    uid,
    title: "New CashRydr Hub listing",
    body: request.tripFormat ? `${request.tripFormat} listing available in CashRydr Hub.` : "A new listing is available in CashRydr Hub.",
    route: { type: "cashHubUpdate", target: "cashHub", requestId: event.params.requestId }
  })));
});

export const onCashHubConversationCreated = onDocumentCreated("cashHubConversations/{conversationId}", async (event) => {
  const conversation = event.data?.data() as CashHubConversation | undefined;
  if (!conversation?.riderUid || !conversation.driverUid || !conversation.requestId) return;

  if (conversation.offerStatus === "pending") {
    await sendPushToUser({
      audience: "rider",
      uid: conversation.riderUid,
      title: "New CashRydr Hub offer",
      body: conversation.driverName
        ? `${conversation.driverName} sent an offer for your listing.`
        : "A driver sent an offer for your CashRydr Hub listing.",
      route: { type: "cashHubOffer", target: "cashHub", requestId: conversation.requestId, chatId: event.params.conversationId }
    });
  }
});

export const onCashHubMessageCreated = onDocumentCreated("cashHubConversations/{conversationId}/messages/{messageId}", async (event) => {
  const message = event.data?.data() as CashHubMessage | undefined;
  if (!message?.senderUid || message.kind === "offer") return;
  const conversationSnap = await db.collection("cashHubConversations").doc(event.params.conversationId).get();
  const conversation = conversationSnap.data() as CashHubConversation | undefined;
  if (!conversation || !conversation.riderUid || !conversation.driverUid || !conversation.requestId) return;
  if (message.kind === "listingTaken") {
    await sendPushToUser({
      audience: "driver",
      uid: conversation.driverUid,
      title: "Cash Hub negotiation ended",
      body: "This negotiation ended because the rider connected with another driver.",
      route: { type: "cashHubUpdate", target: "cashHub", requestId: conversation.requestId, chatId: event.params.conversationId }
    });
    return;
  }
  if (message.kind === "priceAccepted") return;
  if (["cancelled", "completed", "declined", "released", "removed", "ended", "expired", "unavailable"].includes(conversation.status ?? "")) return;

  if ((message.kind === "offerDeclined" || message.kind === "chatEnded") && message.recipientUid) {
    const audience = message.recipientUid === conversation.driverUid ? "driver" : "rider";
    await sendPushToUser({
      audience,
      uid: message.recipientUid,
      title: message.kind === "offerDeclined" ? "Cash Hub price declined" : "Cash Hub chat ended",
      body: message.kind === "offerDeclined" ? "The price was declined, but the negotiation can continue." : "The other participant ended this chat.",
      route: { type: "cashHubMessage", target: "cashHub", requestId: conversation.requestId, chatId: event.params.conversationId }
    });
    return;
  }

  const senderIsRider = message.senderUid === conversation.riderUid || message.senderRole === "rider";
  await conversationSnap.ref.set({ updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await sendPushToUser({
    audience: senderIsRider ? "driver" : "rider",
    uid: senderIsRider ? conversation.driverUid : conversation.riderUid,
    title: "New CashRydr Hub message",
    body: `${message.senderName || (senderIsRider ? "Your rider" : "Your driver")} sent a message.`,
    route: { type: "cashHubMessage", target: "cashHub", requestId: conversation.requestId, chatId: event.params.conversationId }
  });
});

export const onCashHubRequestUpdated = onDocumentUpdated("cashRydrRequests/{requestId}", async (event) => {
  const before = event.data?.before.data() as CashHubRequest | undefined;
  const after = event.data?.after.data() as CashHubRequest | undefined;
  if (!before || !after || !after.riderUid) return;
  const requestId = event.params.requestId;

  if (before.status !== after.status && after.status === "connected" && after.connectedDriverUid) {
    await Promise.all([
      sendPushToUser({
        audience: "rider", uid: after.riderUid, title: "CashRydr Hub connection confirmed",
        body: after.connectedDriverName ? `You are connected with ${after.connectedDriverName}.` : "You are connected with a driver.",
        route: { type: "cashHubUpdate", target: "cashHub", requestId }
      }),
      sendPushToUser({
        audience: "driver", uid: after.connectedDriverUid, title: "CashRydr Hub connection confirmed",
        body: "You are now connected to this rider's listing.",
        route: { type: "cashHubUpdate", target: "cashHub", requestId }
      })
    ]);
    return;
  }

  if (before.status === "connected" && after.status === "open" && before.connectedDriverUid) {
    await sendPushToUser({
      audience: "driver",
      uid: before.connectedDriverUid,
      title: "CashRydr Hub connection ended",
      body: "This listing has been reopened for other drivers.",
      route: { type: "cashHubUpdate", target: "cashHub", requestId }
    });
  }

  if (before.status !== "expired" && after.status === "expired") {
    const recipients: Promise<void>[] = [sendPushToUser({
      audience: "rider", uid: after.riderUid, title: "CashRydr Hub listing expired",
      body: "This listing has closed because its active window ended.",
      route: { type: "cashHubUpdate", target: "cashHub", requestId }
    })];
    if (before.connectedDriverUid) recipients.push(sendPushToUser({
      audience: "driver", uid: before.connectedDriverUid, title: "CashRydr Hub listing expired",
      body: "This connected listing has closed.",
      route: { type: "cashHubUpdate", target: "cashHub", requestId }
    }));
    await Promise.all(recipients);
    return;
  }

  if (before.driverQueueStatus !== after.driverQueueStatus && after.driverQueueStatus && after.status !== "open") {
    const messages: Record<string, string> = {
      confirmed: "Your driver confirmed the listing.",
      arrived: "Your driver has arrived at the pickup location.",
      started: "Your CashRydr Hub trip has started.",
      completed: "Your CashRydr Hub trip has been marked complete."
    };
    const body = messages[after.driverQueueStatus];
    if (body) await sendPushToUser({
      audience: "rider", uid: after.riderUid, title: "CashRydr Hub update", body,
      route: { type: "cashHubUpdate", target: "cashHub", requestId }
    });
  }
});
