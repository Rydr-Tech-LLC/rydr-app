"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function DriverActions({
  uid,
  canApprove,
  missing
}: {
  uid: string;
  canApprove: boolean;
  missing: string[];
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  async function submit(decision: "approved" | "needs_attention" | "rejected") {
    setLoading(decision);
    setError(null);
    try {
      const response = await fetch(`/api/drivers/${uid}/decision`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ decision, reason: reason || undefined })
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? "Something went wrong.");
        return;
      }
      router.push("/drivers");
      router.refresh();
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold text-ink">Driver Actions</h2>

      {!canApprove && (
        <p className="mb-3 rounded-md bg-amber-50 px-3 py-2 text-[11px] text-amber-800">
          Approve disabled — missing: {missing.join(", ")}
        </p>
      )}

      <textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Optional reason (used for Needs Attention / Reject)"
        className="mb-3 w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink"
        rows={2}
      />

      {error && <p className="mb-2 text-xs text-rydr-red">{error}</p>}

      <div className="flex flex-col gap-2">
        <button
          disabled={!canApprove || loading !== null}
          onClick={() => submit("approved")}
          className="rounded-md bg-emerald-600 py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {loading === "approved" ? "Approving…" : "Approve Driver"}
        </button>
        <button
          disabled={loading !== null}
          onClick={() => submit("needs_attention")}
          className="rounded-md bg-amber-500 py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {loading === "needs_attention" ? "Saving…" : "Needs Attention"}
        </button>
        <button
          disabled={loading !== null}
          onClick={() => submit("rejected")}
          className="rounded-md bg-rydr-red py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {loading === "rejected" ? "Rejecting…" : "Reject Driver"}
        </button>
      </div>
    </div>
  );
}
