"use client";
import Link from "next/link";
import { useState } from "react";
import { Inbox, Search, ArrowUpRight, MessageCircle } from "lucide-react";
import StatusPill from "./StatusPill";
export type InboxTicket = {
  id: string;
  subject: string;
  status: string;
  role: string;
  category: string;
  userId: string;
  updated: string;
};
export default function SupportInbox({
  tickets,
  failed = false,
}: {
  tickets: InboxTicket[];
  failed?: boolean;
}) {
  const [status, setStatus] = useState("open");
  const [q, setQ] = useState("");
  const [role, setRole] = useState("all");
  const [selected, setSelected] = useState<string | null>(null);
  const filtered = tickets.filter(
    (t) =>
      (status === "all" || t.status === status) &&
      (role === "all" || t.role === role) &&
      [t.subject, t.category, t.userId, t.id]
        .join(" ")
        .toLowerCase()
        .includes(q.trim().toLowerCase()),
  );
  const ticket = filtered.find((t) => t.id === selected) ?? filtered[0];
  return (
    <div className="space-y-6">
      <div>
        <p className="mc-eyebrow mb-2">Conversations & care</p>
        <h1 className="text-3xl font-semibold tracking-tight">Support Inbox</h1>
        <p className="mt-2 text-sm text-muted">
          One place to help riders and drivers, from first message to
          resolution.
        </p>
      </div>
      <div className="grid grid-cols-3 gap-3">
        {[
          ["Open requests", tickets.filter((t) => t.status === "open").length],
          ["Resolved", tickets.filter((t) => t.status === "closed").length],
          ["Loaded conversations", tickets.length],
        ].map(([name, count]) => (
          <div key={name} className="mc-panel">
            <p className="mc-eyebrow">{name}</p>
            <p className="mt-2 text-3xl font-semibold">
              {failed ? "—" : count}
            </p>
          </div>
        ))}
      </div>
      {failed && (
        <p role="alert" className="rounded-xl bg-red-50 p-4 text-red-800">
          The inbox could not be loaded. Refresh to retry.
        </p>
      )}
      <div className="overflow-hidden rounded-lg border border-line bg-white">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line p-4">
          <div className="mc-segment">
            {["open", "closed", "all"].map((s) => (
              <button
                key={s}
                aria-pressed={status === s}
                onClick={() => setStatus(s)}
                className="capitalize"
              >
                {s === "closed" ? "Resolved" : s}
              </button>
            ))}
          </div>
          <div className="flex flex-wrap gap-2">
            <label className="flex items-center gap-2 rounded-xl border border-line px-3 text-muted">
              <Search size={15} />
              <input
                aria-label="Search support tickets"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Search conversations…"
                className="border-0 bg-transparent text-sm"
              />
            </label>
            <select
              aria-label="Filter support by role"
              value={role}
              onChange={(e) => setRole(e.target.value)}
              className="border border-line px-3 text-xs"
            >
              <option value="all">Everyone</option>
              <option value="driver">Drivers</option>
              <option value="rider">Riders</option>
            </select>
          </div>
        </div>
        <div className="grid min-h-[430px] lg:grid-cols-[minmax(300px,1fr)_1.2fr]">
          <div
            className="max-h-[620px] overflow-y-auto lg:border-r lg:border-line"
            aria-label="Conversations"
          >
            {filtered.map((t) => (
              <button
                key={t.id}
                onClick={() => setSelected(t.id)}
                aria-pressed={ticket?.id === t.id}
                className={`block w-full border-b border-line p-5 text-left ${ticket?.id === t.id ? "bg-red-50/60 shadow-[inset_3px_0_#ed2949]" : "hover:bg-grouped"}`}
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="font-semibold">{t.subject}</span>
                  <StatusPill status={t.status} />
                </div>
                <p className="mt-2 text-xs capitalize text-muted">
                  {t.role} · {t.category || "General support"}
                </p>
                <p className="mt-2 text-[11px] text-muted">
                  {t.updated || "Awaiting first update"}
                </p>
              </button>
            ))}
            {!filtered.length && (
              <div className="mc-empty">
                <Inbox size={36} />
                <p className="font-semibold text-ink">
                  {failed ? "Inbox unavailable" : "You’re all caught up"}
                </p>
                <p className="mt-2 text-sm">
                  {q
                    ? "No conversations match this search."
                    : "No conversations in this view."}
                </p>
              </div>
            )}
          </div>
          <div className="flex flex-col justify-center p-6 sm:p-10">
            {ticket ? (
              <>
                <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-red-100 to-violet-100 text-rydr-burgundy">
                  <MessageCircle size={26} />
                </div>
                <p className="mc-eyebrow">Conversation overview</p>
                <h2 className="mt-3 text-2xl font-semibold tracking-tight">
                  {ticket.subject}
                </h2>
                <dl className="my-6 space-y-4 text-sm">
                  <div className="flex justify-between border-b border-line pb-3">
                    <dt className="text-muted">Status</dt>
                    <dd>
                      <StatusPill status={ticket.status} />
                    </dd>
                  </div>
                  <div className="flex justify-between border-b border-line pb-3">
                    <dt className="text-muted">Category</dt>
                    <dd>{ticket.category || "General support"}</dd>
                  </div>
                  <div className="flex justify-between gap-4 border-b border-line pb-3">
                    <dt className="text-muted">Requested by</dt>
                    <dd className="min-w-0 truncate">
                      {["rider", "driver"].includes(ticket.role) ? (
                        <Link
                          className="text-rydr-burgundy hover:underline"
                          href={`/${ticket.role === "driver" ? "drivers" : "riders"}/${encodeURIComponent(ticket.userId)}`}
                        >
                          View {ticket.role} profile ↗
                        </Link>
                      ) : (
                        ticket.role
                      )}
                    </dd>
                  </div>
                </dl>
                <Link
                  href={`/support/${encodeURIComponent(ticket.id)}`}
                  className="flex w-fit items-center gap-3 rounded-xl bg-rydr-red px-5 py-3 text-sm font-semibold text-white"
                >
                  Open conversation
                  <ArrowUpRight size={17} />
                </Link>
                <p className="mt-4 text-xs leading-relaxed text-muted">
                  Read the thread, reply, or mark it resolved. Sending a reply
                  notifies the account holder.
                </p>
              </>
            ) : (
              <div className="mc-empty">
                <MessageCircle size={38} />
                Select a conversation to get started.
              </div>
            )}
          </div>
        </div>
        <div className="border-t border-line px-5 py-3 text-xs text-muted">
          Showing {filtered.length} of {tickets.length} most recently updated
          conversations · Up to 200 loaded
        </div>
      </div>
    </div>
  );
}
