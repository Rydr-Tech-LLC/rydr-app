"use client";
import {useWorkspaceRouter as useRouter} from "@/components/WorkspaceContext";

import { useState } from "react";
import {WorkspaceLink as Link} from "@/components/WorkspaceContext";


export default function VehicleEntryActions({ vehicleId }: { vehicleId: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [syncMessage, setSyncMessage] = useState<string | null>(null);

  const [pendingPrestine, setPendingPrestine] = useState<{ uid: string; name: string; issues: string[] }[]>([]);

  async function handleSyncDriverProfiles() {
    setLoading(true);
    setSyncMessage(null);
    setPendingPrestine([]);
    try {
      const res = await fetch(`/api/vehicle-library/${vehicleId}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "syncDriverProfiles" })
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        setPendingPrestine(Array.isArray(data.pendingPrestine) ? data.pendingPrestine : []);
        setSyncMessage(`${data.matchedDriverCount ?? 0} driver profile${data.matchedDriverCount === 1 ? "" : "s"} synced. Prestine follows the selected vehicle’s library eligibility automatically.`);
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
      {pendingPrestine.length > 0 && <div role="status" className="max-w-lg rounded-xl border border-amber-300 bg-amber-50 p-4 text-left text-sm text-amber-950">
        <p className="font-semibold">Prestine was not enabled for {pendingPrestine.length} driver{pendingPrestine.length === 1 ? "" : "s"}</p>
        <p className="mt-1">Library settings saved. These vehicles do not currently meet the library or model-year requirements shown below.</p>
        {pendingPrestine.map(driver => <div key={driver.uid} className="mt-3 border-t border-amber-200 pt-2"><Link className="font-semibold underline" href={`/drivers/${encodeURIComponent(driver.uid)}#prestine-approval`}>View {driver.name}’s eligibility →</Link><ul className="mt-1 list-disc pl-5">{driver.issues.map(issue => <li key={issue}>{issue}</li>)}</ul></div>)}
      </div>}
      {syncMessage && <p className="max-w-xs text-left text-xs text-muted sm:text-right">{syncMessage}</p>}
    </div>
  );
}
