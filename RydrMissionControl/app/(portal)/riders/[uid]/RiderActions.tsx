"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { ActiveRideSummary } from "@/lib/activeRideTypes";

export default function RiderActions({
  uid,
  accountStatus,
  hasStudentAmbassadorBadge,
  activeRide
}: {
  uid: string;
  accountStatus: string;
  hasStudentAmbassadorBadge: boolean;
  activeRide: ActiveRideSummary | null;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [deleteError, setDeleteError] = useState<string | null>(null);

  async function setStatus(status: "active" | "suspended") {
    setLoading(status);
    setError(null);
    try {
      const response = await fetch(`/api/riders/${uid}/status`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status, reason: reason || undefined })
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

  async function deleteRider() {
    const confirmed = window.confirm(
      "This permanently deletes this rider's account, sign-in, and Stripe records. This cannot be undone and is separate from the account deletion request queue. Continue?"
    );
    if (!confirmed) return;
    const typed = window.prompt('Type DELETE to confirm permanently deleting this rider.');
    if (typed !== "DELETE") return;

    setLoading("delete");
    setDeleteError(null);
    try {
      const response = await fetch(`/api/riders/${uid}/delete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reason: reason || undefined })
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setDeleteError(body.error ?? "Something went wrong.");
        return;
      }
      router.push("/riders");
      router.refresh();
    } finally {
      setLoading(null);
    }
  }

  async function setStudentAmbassadorBadge(active: boolean) {
    setLoading(active ? "studentAmbassadorOn" : "studentAmbassadorOff");
    setError(null);
    try {
      const response = await fetch(`/api/riders/${uid}/badges/student-ambassador`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ active, reason: reason || undefined })
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

  async function cancelActiveRide() {
    if (!activeRide) return;
    const confirmed = window.confirm(`Cancel active ride ${activeRide.id}? This will end the ride for both rider and driver.`);
    if (!confirmed) return;

    setLoading("cancel_ride");
    setError(null);
    try {
      const response = await fetch(`/api/rides/${activeRide.id}/cancel`, {
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

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold text-ink">Rider Actions</h2>

      <textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Optional reason"
        className="mb-3 w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink"
        rows={2}
      />

      {error && <p className="mb-2 text-xs text-rydr-red">{error}</p>}

      <div className="flex flex-col gap-2">
        {accountStatus === "suspended" ? (
          <button
            disabled={loading !== null}
            onClick={() => setStatus("active")}
            className="rounded-md bg-emerald-600 py-2 text-xs font-semibold text-white transition disabled:opacity-40"
          >
            {loading === "active" ? "Reinstating…" : "Reinstate Rider"}
          </button>
        ) : (
          <button
            disabled={loading !== null}
            onClick={() => setStatus("suspended")}
            className="rounded-md bg-amber-500 py-2 text-xs font-semibold text-white transition disabled:opacity-40"
          >
            {loading === "suspended" ? "Suspending…" : "Suspend Rider"}
          </button>
        )}
      </div>

      {activeRide && (
        <div className="mt-5 border-t border-line pt-4">
          <p className="mb-2 text-[11px] font-medium text-muted">
            Active ride {activeRide.id} · {activeRide.status}
            {activeRide.pickup ? ` · ${activeRide.pickup}` : ""}
          </p>
          <button
            disabled={loading !== null}
            onClick={cancelActiveRide}
            className="w-full rounded-md border border-rydr-red bg-white py-2 text-xs font-semibold text-rydr-red transition hover:bg-rydr-red/5 disabled:opacity-40"
          >
            {loading === "cancel_ride" ? "Cancelling…" : "Cancel Active Ride"}
          </button>
        </div>
      )}

      <div className="mt-5 border-t border-line pt-4">
        <p className="mb-2 text-[11px] font-medium text-muted">
          Manually apply or remove the Student Ambassador badge for beta community liaisons.
        </p>
        {hasStudentAmbassadorBadge ? (
          <button
            disabled={loading !== null}
            onClick={() => setStudentAmbassadorBadge(false)}
            className="w-full rounded-md border border-line bg-white py-2 text-xs font-semibold text-ink transition hover:bg-grouped disabled:opacity-40"
          >
            {loading === "studentAmbassadorOff" ? "Removing…" : "Remove Student Ambassador"}
          </button>
        ) : (
          <button
            disabled={loading !== null}
            onClick={() => setStudentAmbassadorBadge(true)}
            className="w-full rounded-md bg-ink py-2 text-xs font-semibold text-white transition disabled:opacity-40"
          >
            {loading === "studentAmbassadorOn" ? "Assigning…" : "Assign Student Ambassador"}
          </button>
        )}
      </div>

      <div className="mt-5 border-t border-line pt-4">
        <p className="mb-2 text-[11px] font-medium text-muted">
          Permanently delete this rider&apos;s account, sign-in, and Stripe records. No request from the rider
          required — separate from and does not affect the account deletion request queue. This cannot be undone.
        </p>
        {deleteError && <p className="mb-2 text-xs text-rydr-red">{deleteError}</p>}
        <button
          disabled={loading !== null}
          onClick={deleteRider}
          className="w-full rounded-md border border-rydr-red bg-white py-2 text-xs font-semibold text-rydr-red transition hover:bg-rydr-red/5 disabled:opacity-40"
        >
          {loading === "delete" ? "Deleting…" : "Delete Rider (Permanent)"}
        </button>
      </div>
    </div>
  );
}
