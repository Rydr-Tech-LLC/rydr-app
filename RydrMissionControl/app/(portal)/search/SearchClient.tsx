"use client";

import { useState } from "react";
import {WorkspaceLink as Link} from "@/components/WorkspaceContext";

interface Result {
  uid: string;
  name: string;
  email?: string;
}

export default function SearchClient() {
  const [q, setQ] = useState("");
  const [drivers, setDrivers] = useState<Result[]>([]);
  const [riders, setRiders] = useState<Result[]>([]);
  const [error, setError] = useState("");
  const [searched, setSearched] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!q.trim()) return;
    setLoading(true);
    setError("");
    setSearched(false);
    try {
      const response = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
      if (!response.ok)
        throw new Error("Search is unavailable. Please try again.");
      const body = await response.json();
      setSearched(true);
      setDrivers(body.drivers ?? []);
      setRiders(body.riders ?? []);
    } catch (error) {
      setError(
        error instanceof Error
          ? error.message
          : "Search failed. Please try again.",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-6">
      <form onSubmit={handleSearch} className="flex gap-2">
        <input
          aria-label="Search people, vehicles, and plates"
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

      {error && (
        <p role="alert" className="text-sm text-red-700">
          {error}
        </p>
      )}
      {searched && (
        <div className="grid gap-6 sm:grid-cols-2">
          <ResultGroup title="Drivers" results={drivers} hrefBase="/drivers" />
          <ResultGroup title="Riders" results={riders} hrefBase="/riders" />
        </div>
      )}
    </div>
  );
}

function ResultGroup({
  title,
  results,
  hrefBase,
}: {
  title: string;
  results: Result[];
  hrefBase: string;
}) {
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
              href={`${hrefBase}/${r.uid}`}
              className="flex items-center justify-between px-4 py-2.5 text-sm hover:bg-grouped/60"
            >
              <span className="font-medium text-ink">
                {r.name || "Unnamed"}
              </span>
              <span className="text-xs text-muted">{r.email ?? "—"}</span>
            </Link>
          ))
        )}
      </div>
    </div>
  );
}
