"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function SupportReplyForm({
  ticketId,
  isClosed,
}: {
  ticketId: string;
  isClosed: boolean;
}) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    if (!text.trim()) return;
    setSending(true);
    setError(null);
    try {
      const res = await fetch(`/api/support/${ticketId}/reply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        setError(body.error || "Failed to send");
        return;
      }
      setText("");
      router.refresh();
    } catch {
      setError(
        "Connection interrupted. Your reply is still here; please try again.",
      );
    } finally {
      setSending(false);
    }
  }

  async function toggleClosed() {
    setSending(true);
    setError(null);
    try {
      const res = await fetch(`/api/support/${ticketId}/reply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ setStatus: isClosed ? "open" : "closed" }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || "Could not update ticket");
      }
      router.refresh();
    } catch (error) {
      setError(
        error instanceof Error
          ? error.message
          : "Could not update ticket. Try again.",
      );
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="space-y-2 rounded-lg border border-line bg-white p-4 shadow-sm">
      <textarea
        aria-label="Reply to account holder"
        maxLength={10000}
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Write a reply…"
        rows={3}
        className="w-full resize-none rounded-md border border-line bg-grouped p-3 text-sm text-ink outline-none focus:border-ink/30"
      />
      <div className="flex items-center justify-between">
        <button
          onClick={toggleClosed}
          disabled={sending}
          className="rounded-md bg-grouped px-2.5 py-1 text-[11px] font-medium text-ink transition hover:bg-line disabled:opacity-50"
        >
          {isClosed ? "Reopen ticket" : "Close ticket"}
        </button>
        <button
          onClick={send}
          disabled={sending || !text.trim()}
          className="rounded-md bg-rydr-red px-3 py-1.5 text-[12px] font-medium text-white transition hover:bg-rydr-red/90 disabled:opacity-50"
        >
          {sending ? "Sending…" : "Send Reply"}
        </button>
      </div>
      {error && (
        <p role="alert" className="text-[11px] text-rydr-red">
          {error}
        </p>
      )}
    </div>
  );
}
