import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { db, FieldValue } from "../admin";
import { sendPushToUser } from "../services/notificationSender";

interface RideRequestDoc {
  driverId?: string;
  riderId?: string;
  pickup?: string;
  dropoff?: string;
  rideType?: string;
  status?: string;
  dispatchStatus?: string;
  dispatchAttemptNumber?: number;
}

interface RideChatDoc {
  riderId?: string;
  driverId?: string;
  status?: string;
}

interface RideChatMessageDoc {
  senderId?: string;
  senderRole?: string;
}

export const onRideRequestCreated = onDocumentCreated("rideRequests/{requestId}", async (event) => {
  const request = event.data?.data() as RideRequestDoc | undefined;
  if (!request || request.status !== "pending" || request.dispatchStatus !== "offered" || !request.driverId) return;

  await sendPushToUser({
    audience: "driver",
    uid: request.driverId,
    title: "New ride request",
    body: `${request.rideType ?? "Rydr"} request from ${request.pickup ?? "pickup location"}.`,
    route: { type: "newRideRequest", target: "dashboard", requestId: event.params.requestId }
  });
});

export const onRideRequestRematched = onDocumentUpdated("rideRequests/{requestId}", async (event) => {
  const before = event.data?.before.data() as RideRequestDoc | undefined;
  const request = event.data?.after.data() as RideRequestDoc | undefined;
  if (!request || request.status !== "pending" || !request.driverId) return;
  if (!["offered", "rematching"].includes(request.dispatchStatus ?? "")) return;
  const assignmentChanged = before?.driverId !== request.driverId
    || before?.dispatchAttemptNumber !== request.dispatchAttemptNumber
    || before?.dispatchStatus !== request.dispatchStatus;
  if (!assignmentChanged) return;

  await sendPushToUser({
    audience: "driver",
    uid: request.driverId,
    title: "New ride request",
    body: `${request.rideType ?? "Rydr"} request from ${request.pickup ?? "pickup location"}.`,
    route: { type: "newRideRequest", target: "dashboard", requestId: event.params.requestId }
  });
});

export const onRideChatMessageCreated = onDocumentCreated("rideChats/{rideId}/messages/{messageId}", async (event) => {
  const message = event.data?.data() as RideChatMessageDoc | undefined;
  if (!message?.senderId) return;

  const chatSnap = await db.collection("rideChats").doc(event.params.rideId).get();
  const chat = chatSnap.data() as RideChatDoc | undefined;
  if (!chat || chat.status === "closed" || !chat.riderId || !chat.driverId) return;
  await chatSnap.ref.set({ updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  const senderIsRider = message.senderId === chat.riderId || message.senderRole === "rider";
  const audience = senderIsRider ? "driver" : "rider";
  const uid = senderIsRider ? chat.driverId : chat.riderId;

  await sendPushToUser({
    audience,
    uid,
    title: "New ride message",
    body: senderIsRider ? "Your rider sent a message." : "Your driver sent a message.",
    route: { type: "rideMessage", target: "rideChat", rideId: event.params.rideId, chatId: event.params.rideId }
  });
});
