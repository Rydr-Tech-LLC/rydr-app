"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export default function WaitlistActions({ id, status }: { id: string; status: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState<"approved" | "rejected" | "pending" | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function decide(decision: "approved" | "rejected" | "pending") {
    const reason =
      decision === "rejected"
        ? window.prompt("Why is this beta request being rejected? This stays internal.")
        : undefined;

    if (decision === "rejected" && !reason?.trim()) return;

    setBusy(decision);
    setMessage(null);

    try {
      const response = await fetch(`/api/waitlist/${id}/decision`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ decision, reason })
      });
      const payload = (await response.json().catch(() => null)) as { error?: string; emailStatus?: string } | null;

      if (!response.ok) {
        throw new Error(payload?.error ?? "Unable to update waitlist request.");
      }

      const emailNote = decision === "approved" ? ` Approval email: ${payload?.emailStatus ?? "not_sent"}.` : "";
      setMessage(`Updated to ${decision}.${emailNote}`);
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to update waitlist request.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col items-end gap-1.5">
      <div className="flex flex-wrap justify-end gap-1.5">
        <button
          type="button"
          disabled={busy !== null || status === "approved"}
          onClick={() => decide("approved")}
          className="rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40"
        >
          {busy === "approved" ? "Approving..." : "Approve"}
        </button>
        <button
          type="button"
          disabled={busy !== null || status === "pending"}
          onClick={() => decide("pending")}
          className="rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink disabled:cursor-not-allowed disabled:opacity-40"
        >
          Pending
        </button>
        <button
          type="button"
          disabled={busy !== null || status === "rejected"}
          onClick={() => decide("rejected")}
          className="rounded-md bg-red-600 px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40"
        >
          Reject
        </button>
      </div>
      {message && <p className="max-w-xs text-right text-[11px] text-muted">{message}</p>}
    </div>
  );
}
