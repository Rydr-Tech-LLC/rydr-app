"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function VehicleEntryActions({ vehicleId }: { vehicleId: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [syncMessage, setSyncMessage] = useState<string | null>(null);

  async function handleSyncDriverProfiles() {
    setLoading(true);
    setSyncMessage(null);
    try {
      const res = await fetch(`/api/vehicle-library/${vehicleId}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "syncDriverProfiles" })
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        setSyncMessage(`${data.matchedDriverCount ?? 0} driver profile${data.matchedDriverCount === 1 ? "" : "s"} updated.`);
        router.refresh();
      } else {
        setSyncMessage(typeof data.error === "string" ? data.error : "Sync failed.");
      }
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete() {
    if (!confirm(`Delete "${vehicleId}" and all of its images? This cannot be undone.`)) return;
    setLoading(true);
    try {
      const res = await fetch(`/api/vehicle-library/${vehicleId}`, { method: "DELETE" });
      if (res.ok) {
        router.push("/vehicle-library");
        router.refresh();
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex w-full flex-col items-start gap-2 sm:w-auto sm:items-end">
      <div className="flex flex-wrap gap-2">
        <button
          onClick={handleSyncDriverProfiles}
          disabled={loading}
          className="rounded-md border border-line px-3 py-1.5 text-xs font-semibold text-ink disabled:opacity-40"
        >
          {loading ? "Working…" : "Sync Driver Profiles"}
        </button>
        <button
          onClick={handleDelete}
          disabled={loading}
          className="rounded-md border border-rydr-red px-3 py-1.5 text-xs font-semibold text-rydr-red disabled:opacity-40"
        >
          {loading ? "Working…" : "Delete Entry"}
        </button>
      </div>
      {syncMessage && <p className="max-w-xs text-left text-xs text-muted sm:text-right">{syncMessage}</p>}
    </div>
  );
}
