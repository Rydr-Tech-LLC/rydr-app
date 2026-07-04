"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function DriverActions({
  uid,
  missing
}: {
  uid: string;
  missing: string[];
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [deleteError, setDeleteError] = useState<string | null>(null);

  async function deferBackgroundCheck() {
    setLoading("background_bypass");
    setError(null);
    try {
      const response = await fetch(`/api/drivers/${uid}/background-bypass`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reason: reason || undefined })
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? "Something went wrong.");
        return;
      }
      router.refresh();
    } finally {
      setLoading(null);
    }
  }

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

  async function deleteDriver() {
    const confirmed = window.confirm(
      "This permanently deletes this driver's account, sign-in, and Stripe records. This cannot be undone and is separate from the account deletion request queue. Continue?"
    );
    if (!confirmed) return;
    const typed = window.prompt('Type DELETE to confirm permanently deleting this driver.');
    if (typed !== "DELETE") return;

    setLoading("delete");
    setDeleteError(null);
    try {
      const response = await fetch(`/api/drivers/${uid}/delete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reason: reason || undefined })
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setDeleteError(body.error ?? "Something went wrong.");
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

      {missing.length > 0 && (
        <p className="mb-3 rounded-md bg-amber-50 px-3 py-2 text-[11px] text-amber-800">
          Approval override will enable this driver even though these requirements are missing: {missing.join(", ")}
        </p>
      )}

      <textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Optional reason (used for beta deferral / Needs Attention / Reject)"
        className="mb-3 w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink"
        rows={2}
      />

      {error && <p className="mb-2 text-xs text-rydr-red">{error}</p>}

      <div className="flex flex-col gap-2">
        <button
          disabled={loading !== null}
          onClick={deferBackgroundCheck}
          className="rounded-md bg-slate-900 py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {loading === "background_bypass" ? "Saving…" : "Defer Background Check for Beta"}
        </button>
        <button
          disabled={loading !== null}
          onClick={() => submit("approved")}
          className="rounded-md bg-emerald-600 py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {loading === "approved" ? "Approving…" : "Approve Driver & Enable Online"}
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

      <div className="mt-5 border-t border-line pt-4">
        <p className="mb-2 text-[11px] font-medium text-muted">
          Permanently delete this driver's account, sign-in, and Stripe records. No request from the driver
          required — separate from and does not affect the account deletion request queue. This cannot be undone.
        </p>
        {deleteError && <p className="mb-2 text-xs text-rydr-red">{deleteError}</p>}
        <button
          disabled={loading !== null}
          onClick={deleteDriver}
          className="w-full rounded-md border border-rydr-red bg-white py-2 text-xs font-semibold text-rydr-red transition hover:bg-rydr-red/5 disabled:opacity-40"
        >
          {loading === "delete" ? "Deleting…" : "Delete Driver (Permanent)"}
        </button>
      </div>
    </div>
  );
}
