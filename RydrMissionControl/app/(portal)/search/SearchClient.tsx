"use client";

import { useState } from "react";
import Link from "next/link";

interface Result {
  uid: string;
  name: string;
  email?: string;
}

export default function SearchClient() {
  const [q, setQ] = useState("");
  const [drivers, setDrivers] = useState<Result[]>([]);
  const [riders, setRiders] = useState<Result[]>([]);
  const [loading, setLoading] = useState(false);

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!q.trim()) return;
    setLoading(true);
    try {
      const response = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
      const body = await response.json();
      setDrivers(body.drivers ?? []);
      setRiders(body.riders ?? []);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-6">
      <form onSubmit={handleSearch} className="flex gap-2">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Name, email, phone, driver ID, license number, VIN, plate…"
          className="flex-1 rounded-md border border-line bg-white px-3 py-2 text-sm outline-none focus:border-ink"
        />
        <button
          type="submit"
          disabled={loading}
          className="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {loading ? "Searching…" : "Search"}
        </button>
      </form>

      {(drivers.length > 0 || riders.length > 0) && (
        <div className="grid gap-6 sm:grid-cols-2">
          <ResultGroup title="Drivers" results={drivers} hrefBase="/drivers" />
          <ResultGroup title="Riders" results={riders} hrefBase="/riders" />
        </div>
      )}
    </div>
  );
}

function ResultGroup({ title, results, hrefBase }: { title: string; results: Result[]; hrefBase: string }) {
  return (
    <div className="rounded-lg border border-line bg-white shadow-sm">
      <div className="border-b border-line px-4 py-2.5">
        <h2 className="text-sm font-semibold text-ink">{title}</h2>
      </div>
      <div className="divide-y divide-line">
        {results.length === 0 ? (
          <p className="px-4 py-3 text-sm text-muted">No matches.</p>
        ) : (
          results.map((r) => (
            <Link
              key={r.uid}
              href={hrefBase === "/drivers" ? `/drivers/${r.uid}` : hrefBase}
              className="flex items-center justify-between px-4 py-2.5 text-sm hover:bg-grouped/60"
            >
              <span className="font-medium text-ink">{r.name || "Unnamed"}</span>
              <span className="text-xs text-muted">{r.email ?? "—"}</span>
            </Link>
          ))
        )}
      </div>
    </div>
  );
}
