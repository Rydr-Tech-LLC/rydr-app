"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AccountDeletionActions({ id }: { id: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run(action: "complete" | "reject", reason?: string) {
    setLoading(action);
    setError(null);
    try {
      const res = await fetch(`/api/account-deletions/${id}/process`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, reason })
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        setError(body.error || "Action failed");
        return;
      }
      router.refresh();
    } finally {
      setLoading(null);
    }
  }

  return (
    <div>
      <div className="flex flex-wrap gap-1.5">
        <button
          onClick={() => run("complete")}
          disabled={loading !== null}
          className="rounded-md bg-rydr-red px-2.5 py-1 text-[11px] font-medium text-white transition hover:bg-rydr-red/90 disabled:opacity-50"
        >
          {loading === "complete" ? "Deleting…" : "Confirm & Delete Account"}
        </button>
        <button
          onClick={() => {
            const reason = window.prompt("Reason for rejecting this deletion request?") || undefined;
            void run("reject", reason);
          }}
          disabled={loading !== null}
          className="rounded-md bg-grouped px-2.5 py-1 text-[11px] font-medium text-ink transition hover:bg-line disabled:opacity-50"
        >
          {loading === "reject" ? "…" : "Reject"}
        </button>
      </div>
      {error && <p className="mt-1.5 text-[11px] text-rydr-red">{error}</p>}
    </div>
  );
}
