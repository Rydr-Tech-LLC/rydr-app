import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { db } from "../admin";
import { sendPushToUser } from "../services/notificationSender";

interface RideRequestDoc {
  driverId?: string;
  riderId?: string;
  pickup?: string;
  dropoff?: string;
  rideType?: string;
  status?: string;
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
  if (!request || request.status !== "pending" || !request.driverId) return;

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
