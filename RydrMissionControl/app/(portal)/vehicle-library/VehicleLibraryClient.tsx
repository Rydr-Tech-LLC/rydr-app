"use client";

import { useMemo, useState, useTransition } from "react";
import Link from "next/link";
import type { VehicleLibraryEntry } from "@/lib/vehicleLibrary";

const VEHICLE_COLORS = ["Black", "White", "Silver", "Gray", "Blue", "Red", "Green", "Brown", "Gold", "Yellow", "Orange"] as const;
const OPENART_URL = "https://openart.ai/suite/create-image/";

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
    const missing = entries.filter((entry) => imageCount(entry) === 0).length;
    const incomplete = entries.filter((entry) => imageCount(entry) > 0 && imageCount(entry) < VEHICLE_COLORS.length + 1).length;
    const coveredColors = entries.reduce((sum, entry) => sum + (entry.availableColors?.length ?? 0), 0);
    return { total: entries.length, missing, incomplete, coveredColors };
  }, [entries]);

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
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Search failed.");
        return;
      }
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
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard label="Library entries" value={stats.total} />
        <StatCard label="Missing images" value={stats.missing} tone={stats.missing > 0 ? "warn" : "ok"} />
        <StatCard label="Needs color coverage" value={stats.incomplete} tone={stats.incomplete > 0 ? "warn" : "ok"} />
        <StatCard label="Color images stored" value={stats.coveredColors} />
      </div>

      <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
        <div className="flex flex-wrap items-end gap-3">
          <Field label="Make">
            <input value={make} onChange={(event) => setMake(event.target.value)} placeholder="Search make" className={inputClass} />
          </Field>
          <Field label="Model">
            <input value={model} onChange={(event) => setModel(event.target.value)} placeholder="Search model" className={inputClass} />
          </Field>
          <Field label="Year">
            <input value={year} onChange={(event) => setYear(event.target.value)} inputMode="numeric" placeholder="Optional" className={inputClass} />
          </Field>
          <label className="flex items-center gap-2 pb-2 text-xs font-medium text-muted">
            <input type="checkbox" checked={missingOnly} onChange={(event) => setMissingOnly(event.target.checked)} />
            Missing images
          </label>
          <label className="flex items-center gap-2 pb-2 text-xs font-medium text-muted">
            <input type="checkbox" checked={incompleteOnly} onChange={(event) => setIncompleteOnly(event.target.checked)} />
            Incomplete colors
          </label>
          <button
            onClick={runSearch}
            disabled={isPending}
            className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50"
          >
            {isPending ? "Searching" : "Search"}
          </button>
          <button onClick={resetSearch} className="rounded-md border border-line px-4 py-2 text-xs font-medium text-muted">
            Reset
          </button>
          <div className="flex w-full flex-wrap gap-2 sm:ml-auto sm:w-auto">
            <a
              href={OPENART_URL}
              target="_blank"
              rel="noreferrer"
              className="rounded-md border border-rydr-burgundy px-4 py-2 text-xs font-semibold text-rydr-burgundy hover:bg-red-50"
            >
              Create image
            </a>
            <Link href="/vehicle-library/new" className="rounded-md bg-rydr-burgundy px-4 py-2 text-xs font-semibold text-white">
              Add vehicle
            </Link>
          </div>
        </div>
        {error && <p className="mt-3 text-xs text-rydr-red">{error}</p>}
      </div>

      <div className="grid gap-3 xl:grid-cols-2">
        {entries.map((entry) => (
          <VehicleCard key={entry.vehicleId} entry={entry} />
        ))}
        {entries.length === 0 && (
          <div className="rounded-lg border border-dashed border-line bg-white p-8 text-center text-sm text-muted">
            No vehicle library entries match these filters.
          </div>
        )}
      </div>
    </div>
  );
}

const inputClass = "w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink sm:w-40";

function VehicleCard({ entry }: { entry: VehicleLibraryEntry }) {
  const count = imageCount(entry);
  const status = count === 0 ? "Missing images" : count < VEHICLE_COLORS.length + 1 ? "Needs colors" : "Complete";
  const statusTone = count === 0 ? "danger" : count < VEHICLE_COLORS.length + 1 ? "warn" : "ok";
  const previewUrl = entry.defaultImageUrl ?? firstColorImage(entry);

  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <div className="flex flex-col gap-4 sm:flex-row">
        <div className="flex aspect-[4/3] w-full flex-shrink-0 items-center justify-center overflow-hidden rounded-md border border-line bg-grouped sm:h-28 sm:w-36">
          {previewUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={previewUrl} alt={`${entry.make} ${entry.model}`} className="h-full w-full object-cover" />
          ) : (
            <span className="px-4 text-center text-[11px] font-medium text-muted">No image</span>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 className="truncate text-sm font-semibold text-ink">
                {entry.yearStart === entry.yearEnd ? entry.yearStart : `${entry.yearStart}-${entry.yearEnd}`} {entry.make} {entry.model}
              </h2>
              <p className="mt-1 truncate text-xs text-muted">
                {[entry.trim, entry.bodyStyle].filter(Boolean).join(" · ") || "No trim details"}
              </p>
            </div>
            <Badge tone={statusTone}>{status}</Badge>
          </div>

          <div className="mt-3">
            <div className="flex items-center justify-between text-[11px] text-muted">
              <span>Color coverage</span>
              <span>{entry.availableColors?.length ?? 0}/{VEHICLE_COLORS.length}</span>
            </div>
            <div className="mt-1 grid grid-cols-11 gap-1">
              {VEHICLE_COLORS.map((color) => (
                <div
                  key={color}
                  title={color}
                  className={`h-2 rounded-full ${entry.colorImages?.[color] ? "bg-rydr-burgundy" : "bg-line"}`}
                />
              ))}
            </div>
          </div>

          <div className="mt-3 flex flex-wrap items-center gap-2">
            {(entry.eligibleRideTypes ?? []).length > 0 ? (
              entry.eligibleRideTypes?.map((rideType) => <Badge key={rideType} tone="neutral">{rideType}</Badge>)
            ) : (
              <Badge tone="warn">Manual eligibility</Badge>
            )}
          </div>

          <div className="mt-4 flex gap-2">
            <Link href={`/vehicle-library/${entry.vehicleId}`} className="rounded-md bg-ink px-3 py-1.5 text-xs font-semibold text-white">
              Manage
            </Link>
            <a
              href={OPENART_URL}
              target="_blank"
              rel="noreferrer"
              className="rounded-md border border-line px-3 py-1.5 text-xs font-medium text-muted hover:bg-grouped"
            >
              Create image
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}

function imageCount(entry: VehicleLibraryEntry) {
  return (entry.defaultImage ? 1 : 0) + Object.keys(entry.colorImages ?? {}).length;
}

function firstColorImage(entry: VehicleLibraryEntry) {
  return Object.values(entry.colorImageUrls ?? {}).find(Boolean) ?? null;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex w-full flex-col gap-1 sm:w-auto">
      <span className="text-[11px] font-medium text-muted">{label}</span>
      {children}
    </div>
  );
}

function StatCard({ label, value, tone }: { label: string; value: number; tone?: "warn" | "ok" }) {
  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <p className="text-[11px] font-medium text-muted">{label}</p>
      <p className={`mt-1 text-2xl font-semibold ${tone === "warn" ? "text-amber-600" : tone === "ok" ? "text-emerald-600" : "text-ink"}`}>{value}</p>
    </div>
  );
}

function Badge({ tone, children }: { tone: "ok" | "warn" | "danger" | "neutral"; children: React.ReactNode }) {
  const styles =
    tone === "ok"
      ? "bg-emerald-50 text-emerald-700"
      : tone === "warn"
        ? "bg-amber-50 text-amber-700"
        : tone === "danger"
          ? "bg-red-50 text-rydr-red"
          : "bg-grouped text-muted";
  return <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${styles}`}>{children}</span>;
}
