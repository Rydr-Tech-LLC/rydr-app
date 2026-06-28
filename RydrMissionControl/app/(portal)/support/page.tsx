import Link from "next/link";
import { adminDb } from "@/lib/firebaseAdmin";
import type { SupportTicketRecord } from "@/lib/types";
import { toDateSafe, timeAgo } from "@/lib/format";
import StatusPill from "@/components/StatusPill";

export const dynamic = "force-dynamic";

export default async function SupportPage() {
  const snap = await adminDb
    .collection("supportTickets")
    .orderBy("updatedAt", "desc")
    .limit(200)
    .get()
    .catch(() => null);

  const tickets = snap ? snap.docs.map((doc) => ({ ...(doc.data() as SupportTicketRecord), id: doc.id })) : [];
  const open = tickets.filter((t) => (t.status ?? "open") === "open");
  const closed = tickets.filter((t) => t.status === "closed");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Support Inbox</h1>
        <p className="mt-1 text-sm text-muted">
          Rider and driver support tickets. Replies sent here are written with the Admin SDK so the rider/driver
          gets a push notification automatically (see onSupportMessageCreated).
        </p>
      </div>

      <TicketGroup title="Open" tickets={open} emptyText="No open tickets." />
      <TicketGroup title="Closed" tickets={closed} emptyText="No closed tickets yet." />
    </div>
  );
}

function TicketGroup({ title, tickets, emptyText }: { title: string; tickets: SupportTicketRecord[]; emptyText: string }) {
  return (
    <div className="space-y-2">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">{title}</h2>
      {tickets.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-6 text-center text-sm text-muted">
          {emptyText}
        </div>
      ) : (
        tickets.map((ticket) => {
          const updated = toDateSafe(ticket.updatedAt) ?? toDateSafe(ticket.createdAt);
          return (
            <Link
              key={ticket.id}
              href={`/support/${ticket.id}`}
              className="block rounded-lg border border-line bg-white p-4 shadow-sm transition hover:border-ink/20"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <p className="font-medium text-ink">{ticket.subject ?? "Support request"}</p>
                  <StatusPill status={ticket.status ?? "open"} />
                  {ticket.userRole && (
                    <span className="rounded-full border border-line bg-grouped px-2 py-0.5 text-[11px] font-medium text-muted">
                      {ticket.userRole}
                    </span>
                  )}
                </div>
                <span className="text-xs text-muted">{updated ? timeAgo(updated) : "—"}</span>
              </div>
              {ticket.category && <p className="mt-1 text-xs text-muted">{ticket.category}</p>}
            </Link>
          );
        })
      )}
    </div>
  );
}
