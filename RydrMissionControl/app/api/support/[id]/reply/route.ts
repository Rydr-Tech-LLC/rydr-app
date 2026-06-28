import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

// Writes admin replies with the Admin SDK so they bypass the client-facing
// Firestore rule that restricts `senderRole` to "rider"|"driver" — only this
// privileged path can ever write `senderRole: "admin"`. That field is what
// the `onSupportMessageCreated` Cloud Function trigger checks before
// pushing a notification to the ticket's owner, so every reply sent here
// reaches the rider/driver automatically.
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json()) as { text?: string; setStatus?: "open" | "closed" };

  const ticketRef = adminDb.collection("supportTickets").doc(params.id);
  const ticketSnap = await ticketRef.get();
  if (!ticketSnap.exists) return NextResponse.json({ error: "Ticket not found" }, { status: 404 });

  if (body.setStatus) {
    await ticketRef.set({ status: body.setStatus, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: body.setStatus === "closed" ? "Support Ticket Closed" : "Support Ticket Reopened",
      targetType: "supportTicket",
      targetId: params.id
    });
    return NextResponse.json({ ok: true });
  }

  const text = (body.text ?? "").trim();
  if (!text) return NextResponse.json({ error: "text is required" }, { status: 400 });

  await ticketRef.collection("messages").add({
    senderId: session.uid,
    senderRole: "admin",
    text,
    createdAt: FieldValue.serverTimestamp()
  });
  await ticketRef.set({ updatedAt: FieldValue.serverTimestamp(), status: "open" }, { merge: true });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Support Reply Sent",
    targetType: "supportTicket",
    targetId: params.id
  });

  return NextResponse.json({ ok: true });
}
