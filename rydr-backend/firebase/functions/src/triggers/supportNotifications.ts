// "Support reply" push notification trigger (Part 9 of the hardening sprint).
//
// Mission Control writes admin replies into
// `supportTickets/{ticketId}/messages/{messageId}` with `senderRole: "admin"`
// via the Admin SDK (see firestore.rules — clients can only create messages
// with their own uid/role; only an admin reply should ever have
// senderRole == "admin"). When that happens, notify whichever rider/driver
// owns the ticket.

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { db } from "../admin";
import { sendPushToUser } from "../services/notificationSender";

interface SupportMessageDoc {
  senderId?: string;
  senderRole?: "rider" | "driver" | "admin";
  text?: string;
}

interface SupportTicketDoc {
  userId?: string;
  userRole?: "rider" | "driver";
  subject?: string;
}

export const onSupportMessageCreated = onDocumentCreated(
  "supportTickets/{ticketId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data() as SupportMessageDoc | undefined;
    if (!message || message.senderRole !== "admin") return;

    const ticketId = event.params.ticketId;
    const ticketSnap = await db.collection("supportTickets").doc(ticketId).get();
    if (!ticketSnap.exists) return;

    const ticket = ticketSnap.data() as SupportTicketDoc;
    if (!ticket.userId || !ticket.userRole) return;

    const preview = (message.text ?? "").trim();
    await sendPushToUser({
      audience: ticket.userRole,
      uid: ticket.userId,
      title: "New reply from Rydr Support",
      body: preview.length > 0 ? preview.slice(0, 140) : "Support replied to your ticket.",
      route: { type: "supportReply", target: "supportTicket", requestId: ticketId }
    });
  }
);
