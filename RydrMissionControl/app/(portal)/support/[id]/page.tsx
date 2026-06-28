import { notFound } from "next/navigation";
import { adminDb } from "@/lib/firebaseAdmin";
import type { SupportMessageRecord, SupportTicketRecord } from "@/lib/types";
import { toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import SupportReplyForm from "./SupportReplyForm";

export const dynamic = "force-dynamic";

export default async function SupportTicketPage({ params }: { params: { id: string } }) {
  const ticketRef = adminDb.collection("supportTickets").doc(params.id);
  const ticketSnap = await ticketRef.get();
  if (!ticketSnap.exists) notFound();
  const ticket = { ...(ticketSnap.data() as SupportTicketRecord), id: ticketSnap.id };

  const messagesSnap = await ticketRef.collection("messages").orderBy("createdAt", "asc").limit(500).get();
  const messages = messagesSnap.docs.map((doc) => ({ ...(doc.data() as SupportMessageRecord), id: doc.id }));

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-semibold text-ink">{ticket.subject ?? "Support request"}</h1>
          <StatusPill status={ticket.status ?? "open"} />
        </div>
        <p className="mt-1 text-sm text-muted">
          {ticket.userRole ?? "user"} {ticket.userId} {ticket.category ? `· ${ticket.category}` : ""}
        </p>
      </div>

      <div className="space-y-3 rounded-lg border border-line bg-white p-4 shadow-sm">
        {messages.length === 0 ? (
          <p className="text-sm text-muted">No messages yet.</p>
        ) : (
          messages.map((message) => {
            const created = toDateSafe(message.createdAt);
            const isAdmin = message.senderRole === "admin";
            return (
              <div key={message.id} className={`flex ${isAdmin ? "justify-end" : "justify-start"}`}>
                <div
                  className={`max-w-[80%] rounded-2xl px-3.5 py-2.5 text-sm ${
                    isAdmin ? "bg-ink text-white" : "bg-grouped text-ink"
                  }`}
                >
                  <p>{message.text}</p>
                  <p className={`mt-1 text-[10px] ${isAdmin ? "text-white/60" : "text-muted"}`}>
                    {isAdmin ? "Rydr Support" : message.senderRole} · {created ? created.toLocaleString() : "—"}
                  </p>
                </div>
              </div>
            );
          })
        )}
      </div>

      <SupportReplyForm ticketId={ticket.id} isClosed={ticket.status === "closed"} />
    </div>
  );
}
