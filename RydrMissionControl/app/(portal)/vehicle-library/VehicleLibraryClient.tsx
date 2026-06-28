"use client";

import { useMemo, useState, useTransition } from "react";
import Link from "next/link";
import type { VehicleLibraryEntry } from "@/lib/vehicleLibrary";

const TOTAL_COLORS = 11;

export default function VehicleLibraryClient({
  initialEntries,
  initialMake = "",
  initialModel = ""
}: {
  initialEntries: VehicleLibraryEntry[];
  initialMake?: string;
  initialModel?: string;
}) {
  const [entries, setEntries] = useState(initialEntries);
  const [make, setMake] = useState(initialMake);
  const [model, setModel] = useState(initialModel);
  const [year, setYear] = useState("");
  const [missingOnly, setMissingOnly] = useState(false);
  const [incompleteOnly, setIncompleteOnly] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const stats = useMemo(() => {
    const missing = initialEntries.filter((e) => !e.defaultImage && Object.keys(e.colorImages ?? {}).length === 0).length;
    const incomplete = initialEntries.filter(
      (e) => (e.availableColors?.length ?? 0) > 0 && (e.availableColors?.length ?? 0) < TOTAL_COLORS
    ).length;
    return { total: initialEntries.length, missing, incomplete };
  }, [initialEntries]);

  function runSearch() {
    setError(null);
    const params = new URLSearchParams();
    if (make.trim()) params.set("make", make.trim());
    if (model.trim()) params.set("model", model.trim());
    if (year.trim()) params.set("year", year.trim());
    if (missingOnly) params.set("missingImagesOnly", "1");
    if (incompleteOnly) params.set("incompleteColorsOnly", "1");

    startTransition(async () => {
      const res = await fetch(`/api/vehicle-library?${params.toString()}`);
      if (!res.ok) {
        setError("Search failed.");
        return;
      }
      const body = await res.json();
      setEntries(body.entries ?? []);
    });
  }

  function resetSearch() {
    setMake("");
    setModel("");
    setYear("");
    setMissingOnly(false);
    setIncompleteOnly(false);
    setEntries(initialEntries);
    setError(null);
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-3">
        <StatCard label="Total entries" value={stats.total} />
        <StatCard label="Missing all images" value={stats.missing} tone={stats.missing > 0 ? "warn" : "ok"} />
        <StatCard label="Incomplete color sets" value={stats.incomplete} tone={stats.incomplete > 0 ? "warn" : "ok"} />
      </div>

      <div className="flex flex-wrap items-end gap-3 rounded-lg border border-line bg-white p-4 shadow-sm">
        <Field label="Make">
          <input value={make} onChange={(e) => setMake(e.target.value)} placeholder="Toyota" className={inputClass} />
        </Field>
        <Field label="Model">
          <input value={model} onChange={(e) => setModel(e.target.value)} placeholder="Camry" className={inputClass} />
        </Field>
        <Field label="Year">
          <input value={year} onChange={(e) => setYear(e.target.value)} placeholder="2022" className={inputClass} />
        </Field>
        <label className="flex items-center gap-1.5 pb-1.5 text-xs font-medium text-muted">
          <input type="checkbox" checked={missingOnly} onChange={(e) => setMissingOnly(e.target.checked)} />
          Missing images
        </label>
        <label className="flex items-center gap-1.5 pb-1.5 text-xs font-medium text-muted">
          <input type="checkbox" checked={incompleteOnly} onChange={(e) => setIncompleteOnly(e.target.checked)} />
          Incomplete colors
        </label>
        <button
          onClick={runSearch}
          disabled={isPending}
          className="rounded-md bg-ink px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
        >
          {isPending ? "Searching…" : "Search"}
        </button>
        <button onClick={resetSearch} className="rounded-md border border-line px-3 py-1.5 text-xs font-medium text-muted">
          Reset
        </button>
        <Link href="/vehicle-library/new" className="ml-auto rounded-md bg-rydr-burgundy px-3 py-1.5 text-xs font-semibold text-white">
          + Add Vehicle
        </Link>
      </div>

      {error && <p className="text-xs text-rydr-red">{error}</p>}

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <table className="w-full text-sm">
          <thead className="border-b border-line bg-grouped text-left text-xs font-medium text-muted">
            <tr>
              <th className="px-4 py-2.5">Vehicle</th>
              <th className="px-4 py-2.5">Years</th>
              <th className="px-4 py-2.5">Trim</th>
              <th className="px-4 py-2.5">Body Style</th>
              <th className="px-4 py-2.5">Colors</th>
              <th className="px-4 py-2.5">Image Status</th>
              <th className="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {entries.map((entry) => {
              const colorCount = entry.availableColors?.length ?? 0;
              const hasAnyImage = Boolean(entry.defaultImage) || colorCount > 0;
              return (
                <tr key={entry.vehicleId} className="hover:bg-grouped/60">
                  <td className="px-4 py-2.5 font-medium text-ink">
                    {entry.make} {entry.model}
                  </td>
                  <td className="px-4 py-2.5 text-muted">
                    {entry.yearStart === entry.yearEnd ? entry.yearStart : `${entry.yearStart}–${entry.yearEnd}`}
                  </td>
                  <td className="px-4 py-2.5 text-muted">{entry.trim ?? "—"}</td>
                  <td className="px-4 py-2.5 text-muted">{entry.bodyStyle}</td>
                  <td className="px-4 py-2.5 text-muted">
                    {colorCount}/{TOTAL_COLORS}
                  </td>
                  <td className="px-4 py-2.5">
                    {!hasAnyImage ? (
                      <Badge tone="danger">No images</Badge>
                    ) : colorCount < TOTAL_COLORS ? (
                      <Badge tone="warn">Incomplete</Badge>
                    ) : (
                      <Badge tone="ok">Complete</Badge>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <Link href={`/vehicle-library/${entry.vehicleId}`} className="text-xs font-semibold text-rydr-burgundy hover:underline">
                      Manage
                    </Link>
                  </td>
                </tr>
              );
            })}
            {entries.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-muted">
                  No vehicle library entries match these filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

const inputClass = "w-32 rounded-md border border-line bg-grouped px-2.5 py-1.5 text-xs outline-none focus:border-ink";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-[11px] font-medium text-muted">{label}</span>
      {children}
    </div>
  );
}

function StatCard({ label, value, tone }: { label: string; value: number; tone?: "warn" | "ok" }) {
  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <p className="text-[11px] font-medium text-muted">{label}</p>
      <p className={`mt-1 text-2xl font-semibold ${tone === "warn" ? "text-amber-600" : "text-ink"}`}>{value}</p>
    </div>
  );
}

function Badge({ tone, children }: { tone: "ok" | "warn" | "danger"; children: React.ReactNode }) {
  const styles =
    tone === "ok" ? "bg-emerald-50 text-emerald-700" : tone === "warn" ? "bg-amber-50 text-amber-700" : "bg-red-50 text-rydr-red";
  return <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${styles}`}>{children}</span>;
}
