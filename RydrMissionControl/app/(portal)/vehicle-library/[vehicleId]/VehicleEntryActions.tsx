"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function VehicleEntryActions({ vehicleId }: { vehicleId: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

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
    <button
      onClick={handleDelete}
      disabled={loading}
      className="rounded-md border border-rydr-red px-3 py-1.5 text-xs font-semibold text-rydr-red disabled:opacity-40"
    >
      {loading ? "Deleting…" : "Delete Entry"}
    </button>
  );
}
