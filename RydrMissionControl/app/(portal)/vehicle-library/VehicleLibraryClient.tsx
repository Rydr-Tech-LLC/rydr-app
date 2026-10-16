"use client";
import { vehicleImageSearchUrl } from "@/lib/vehicleImageSearch";

import { useMemo, useState, useTransition } from "react";
import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import type { VehicleLibraryEntry } from "@/lib/vehicleLibrary";

const VEHICLE_COLORS = [
  "Black",
  "White",
  "Silver",
  "Gray",
  "Blue",
  "Red",
  "Green",
  "Brown",
  "Gold",
  "Yellow",
  "Orange",
] as const;

export default function VehicleLibraryClient({
  initialEntries,
  initialMake = "",
  initialModel = "",
}: {
  initialEntries: VehicleLibraryEntry[];
  initialMake?: string;
  initialModel?: string;
}) {
  const [entries, setEntries] = useState(initialEntries);
  const [make, setMake] = useState(initialMake);
  const [model, setModel] = useState(initialModel);
  const [year, setYear] = useState("");
  const [unverifiedSpecsOnly, setUnverifiedSpecsOnly] = useState(false);
  const [missingOnly, setMissingOnly] = useState(false);
  const [incompleteOnly, setIncompleteOnly] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [rideType, setRideType] = useState("");
  const [error, setError] = useState<string | null>(null);

  const stats = useMemo(() => {
    const missing = entries.filter((entry) => imageCount(entry) === 0).length;
    const incomplete = entries.filter(
      (entry) =>
        imageCount(entry) > 0 &&
        Object.keys(entry.colorImages ?? {}).length < VEHICLE_COLORS.length,
    ).length;
    const coveredColors = entries.reduce(
      (sum, entry) => sum + (entry.availableColors?.length ?? 0),
      0,
    );
    return {
      total: entries.length,
      missing,
      incomplete,
      coveredColors,
      reviewedSpecs: entries.filter(
        (entry) => entry.specifications?.verified === true,
      ).length,
    };
  }, [entries]);

  function runSearch(override?: URLSearchParams) {
    setError(null);
    const params = override ?? new URLSearchParams();
    if (!override) {
      if (make.trim()) params.set("make", make.trim());
      if (model.trim()) params.set("model", model.trim());
      if (year.trim()) params.set("year", year.trim());
      if (missingOnly) params.set("missingImagesOnly", "1");
      if (incompleteOnly) params.set("incompleteColorsOnly", "1");
    }
    startTransition(async () => {
      try {
        const res = await fetch(`/api/vehicle-library?${params.toString()}`);
        const body = await res.json().catch(() => ({}));
        if (!res.ok) {
          setError(body.error ?? "Search failed.");
          return;
        }
        setEntries(body.entries ?? []);
      } catch {
        setError("Vehicle search is unavailable. Please try again.");
      }
    });
  }

  function resetSearch() {
    setMake("");
    setModel("");
    setYear("");
    setUnverifiedSpecsOnly(false);
    setRideType("");
    setMissingOnly(false);
    setIncompleteOnly(false);
    setEntries(initialEntries);
    setError(null);
    runSearch(new URLSearchParams());
  }

  const visibleEntries = entries.filter(
    (entry) =>
      (!unverifiedSpecsOnly || entry.specifications?.verified !== true) &&
      (!rideType ||
        entry.eligibleRideTypes?.some((value) => value === rideType)) &&
      (!missingOnly || imageCount(entry) === 0) &&
      (!incompleteOnly ||
        (imageCount(entry) > 0 &&
          Object.keys(entry.colorImages ?? {}).length < VEHICLE_COLORS.length)),
  );

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <StatCard label="Library entries" value={stats.total} />
        <StatCard
          onClick={() => {
            setMissingOnly(!missingOnly);
            setIncompleteOnly(false);
          }}
          active={missingOnly}
          label="Missing images"
          value={stats.missing}
          tone={stats.missing > 0 ? "warn" : "ok"}
        />
        <StatCard
          onClick={() => {
            setIncompleteOnly(!incompleteOnly);
            setMissingOnly(false);
          }}
          active={incompleteOnly}
          label="Needs color coverage"
          value={stats.incomplete}
          tone={stats.incomplete > 0 ? "warn" : "ok"}
        />
        <StatCard label="Color images stored" value={stats.coveredColors} />
        <StatCard label="Specifications reviewed" value={stats.reviewedSpecs} />
        <StatCard
          onClick={() => setUnverifiedSpecsOnly(!unverifiedSpecsOnly)}
          active={unverifiedSpecsOnly}
          label="Specifications need review"
          value={stats.total - stats.reviewedSpecs}
          tone={stats.total > stats.reviewedSpecs ? "warn" : "ok"}
        />
      </div>

      <div className="rounded-2xl border border-line bg-white p-5 shadow-sm">
        <form
          onSubmit={(event) => {
            event.preventDefault();
            runSearch();
          }}
          className="flex flex-wrap items-end gap-3"
        >
          <Field label="Make">
            <input
              value={make}
              onChange={(event) => setMake(event.target.value)}
              placeholder="Search make"
              className={inputClass}
            />
          </Field>
          <Field label="Model">
            <input
              value={model}
              onChange={(event) => setModel(event.target.value)}
              placeholder="Search model"
              className={inputClass}
            />
          </Field>
          <label className="flex items-center gap-2 text-xs text-muted">
            <input
              type="checkbox"
              checked={unverifiedSpecsOnly}
              onChange={(event) => setUnverifiedSpecsOnly(event.target.checked)}
            />{" "}
            Needs specification review
          </label>
          <Field label="Year">
            <input
              value={year}
              onChange={(event) => setYear(event.target.value)}
              inputMode="numeric"
              placeholder="Optional"
              className={inputClass}
            />
          </Field>
          <label className="flex items-center gap-2 pb-2 text-xs font-medium text-muted">
            <input
              type="checkbox"
              checked={missingOnly}
              onChange={(event) => setMissingOnly(event.target.checked)}
            />
            Missing images
          </label>
          <label className="flex items-center gap-2 pb-2 text-xs font-medium text-muted">
            <input
              type="checkbox"
              checked={incompleteOnly}
              onChange={(event) => setIncompleteOnly(event.target.checked)}
            />
            Incomplete colors
          </label>
          <button
            type="submit"
            disabled={isPending}
            className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50"
          >
            {isPending ? "Searching" : "Search"}
          </button>
          <button
            type="button"
            onClick={() => resetSearch()}
            className="rounded-md border border-line px-4 py-2 text-xs font-medium text-muted"
          >
            Reset
          </button>
          <div className="flex w-full flex-wrap gap-2 sm:ml-auto sm:w-auto">
            <a
              href={vehicleImageSearchUrl({ make, model, yearStart: year })}
              target="_blank"
              rel="noreferrer"
              className="rounded-md border border-rydr-burgundy px-4 py-2 text-xs font-semibold text-rydr-burgundy hover:bg-red-50"
            >
              Search Google Images
            </a>
            <Link
              href="/vehicle-library/new"
              className="rounded-md bg-rydr-burgundy px-4 py-2 text-xs font-semibold text-white"
            >
              Add vehicle
            </Link>
          </div>
        </form>
        <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-line pt-4">
          <span className="mr-2 text-xs font-semibold text-muted">
            Ride eligibility
          </span>
          {["", "Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine"].map(
            (value) => (
              <button
                key={value}
                type="button"
                aria-pressed={rideType === value}
                onClick={() => setRideType(value)}
                className={`rounded-full px-4 py-2 text-xs font-semibold transition ${rideType === value ? "bg-gradient-to-r from-red-500 via-fuchsia-600 to-blue-600 text-white shadow-sm" : "bg-grouped text-muted hover:bg-red-50"}`}
              >
                {value || "All vehicles"}
              </button>
            ),
          )}
        </div>
        {error && <p className="mt-3 text-xs text-rydr-red">{error}</p>}
      </div>

      <div className="flex items-center justify-between text-sm">
        <p className="font-semibold text-ink">
          {visibleEntries.length} vehicles
        </p>
        <p className="text-xs text-muted">
          Select a color to preview · Open a vehicle to manage
        </p>
      </div>
      <div className="grid gap-5 xl:grid-cols-2">
        {visibleEntries.map((entry) => (
          <VehicleCard key={entry.vehicleId} entry={entry} />
        ))}
        {visibleEntries.length === 0 && (
          <div className="rounded-lg border border-dashed border-line bg-white p-8 text-center text-sm text-muted">
            No vehicles match these filters. Try another make or ride type, or
            reset your search.
          </div>
        )}
      </div>
    </div>
  );
}

const inputClass =
  "w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink sm:w-40";

function VehicleCard({ entry }: { entry: VehicleLibraryEntry }) {
  const count = imageCount(entry);
  const status =
    count === 0
      ? "Missing images"
      : Object.keys(entry.colorImages ?? {}).length < VEHICLE_COLORS.length
        ? "Needs colors"
        : "Complete";
  const statusTone =
    count === 0
      ? "danger"
      : Object.keys(entry.colorImages ?? {}).length < VEHICLE_COLORS.length
        ? "warn"
        : "ok";
  const [selectedColor, setSelectedColor] = useState<
    (typeof VEHICLE_COLORS)[number] | null
  >(null);
  const previewUrl = selectedColor
    ? entry.colorImageUrls?.[selectedColor]
    : (entry.defaultImageUrl ?? firstColorImage(entry));

  return (
    <div className="group rounded-2xl border border-line bg-white p-5 shadow-sm transition duration-200 hover:-translate-y-0.5 hover:border-fuchsia-200 hover:shadow-lg motion-reduce:transform-none">
      <div className="flex flex-col gap-4">
        <div className="relative flex aspect-[16/7] w-full items-center justify-center overflow-hidden rounded-xl border border-line bg-gradient-to-br from-red-50 via-white to-blue-50">
          {previewUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={previewUrl}
              alt={`${entry.make} ${entry.model}`}
              className="h-full w-full object-contain p-3 transition duration-300 group-hover:scale-105 motion-reduce:transform-none"
            />
          ) : (
            <span className="px-4 text-center text-[11px] font-medium text-muted">
              {selectedColor
                ? `${selectedColor} image needed — search below to find one`
                : "Image needed — open this vehicle to add one"}
            </span>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 className="truncate text-sm font-semibold text-ink">
                {entry.yearStart === entry.yearEnd
                  ? entry.yearStart
                  : `${entry.yearStart}-${entry.yearEnd}`}{" "}
                {entry.make} {entry.model}
              </h2>
              <p className="mt-1 truncate text-xs text-muted">
                {[entry.trim, entry.bodyStyle].filter(Boolean).join(" · ") ||
                  "No trim details"}
              </p>
            </div>
            <Badge tone={statusTone}>{status}</Badge>
          </div>

          <p className="mt-2 text-xs text-muted">
            Seats including driver:{" "}
            {entry.specifications?.seatCapacity != null
              ? entry.specifications.seatCapacity >= 8
                ? `8+ (${entry.specifications.seatCapacity} total)`
                : entry.specifications.seatCapacity
              : "Unknown"}{" "}
            ·{" "}
            {entry.specifications?.luxuryClassification === "luxury"
              ? "Luxury"
              : entry.specifications?.luxuryClassification === "standard"
                ? "Standard"
                : "Classification pending"}{" "}
            ·{" "}
            {entry.specifications?.verified
              ? "Source reviewed"
              : "Needs specification review"}
          </p>
          <div className="mt-3">
            <div className="flex items-center justify-between text-[11px] text-muted">
              <span>Color coverage</span>
              <span>
                {entry.availableColors?.length ?? 0}/{VEHICLE_COLORS.length}
              </span>
            </div>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                aria-pressed={selectedColor === null}
                onClick={() => setSelectedColor(null)}
                className={`rounded-full border px-3 py-1 text-xs ${selectedColor === null ? "border-fuchsia-500 text-fuchsia-700" : "border-line text-muted"}`}
              >
                Default
              </button>
              {VEHICLE_COLORS.map((color) => (
                <button
                  key={color}
                  type="button"
                  title={
                    entry.colorImageUrls?.[color]
                      ? `Preview ${color}`
                      : `${color} image not yet added — select to search`
                  }
                  aria-label={`Preview ${color}`}
                  aria-pressed={selectedColor === color}
                  onClick={() => setSelectedColor(color)}
                  className={`h-7 w-7 rounded-full border-2 transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-fuchsia-600 ${selectedColor === color ? "ring-2 ring-fuchsia-500 ring-offset-2" : "border-gray-200"} disabled:opacity-20 disabled:cursor-not-allowed`}
                  style={{ backgroundColor: color.toLowerCase() }}
                />
              ))}
            </div>
          </div>

          <div className="mt-3 flex flex-wrap items-center gap-2">
            {(entry.eligibleRideTypes ?? []).length > 0 ? (
              entry.eligibleRideTypes?.map((rideType) => (
                <Badge key={rideType} tone="neutral">
                  {rideType === "Rydr Prestine" ? `Rydr Prestine ${entry.bodyStyle === "suv" ? "SUV" : entry.bodyStyle === "sedan" ? "Sedan" : "— body review needed"}` : rideType}
                </Badge>
              ))
            ) : (
              <Badge tone="warn">Manual eligibility</Badge>
            )}
          </div>

          <div className="mt-4 flex gap-2">
            <Link
              href={`/vehicle-library/${entry.vehicleId}`}
              className="rounded-xl bg-gradient-to-r from-red-500 via-fuchsia-600 to-blue-600 px-4 py-2.5 text-xs font-semibold text-white shadow-sm"
            >
              {entry.specifications?.verified !== true
                ? "Review specifications"
                : count === 0
                  ? "Add vehicle images"
                  : "Manage vehicle"}
            </Link>
            <a
              href={vehicleImageSearchUrl(entry, selectedColor ?? undefined)}
              target="_blank"
              rel="noreferrer"
              className="rounded-md border border-line px-3 py-1.5 text-xs font-medium text-muted hover:bg-grouped"
            >
              {selectedColor
                ? `Find ${selectedColor} image`
                : "Search Google Images"}
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}

function imageCount(entry: VehicleLibraryEntry) {
  return (
    (entry.defaultImage ? 1 : 0) + Object.keys(entry.colorImages ?? {}).length
  );
}

function firstColorImage(entry: VehicleLibraryEntry) {
  return Object.values(entry.colorImageUrls ?? {}).find(Boolean) ?? null;
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="flex w-full flex-col gap-1 sm:w-auto">
      <span className="text-[11px] font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}

function StatCard({
  label,
  value,
  tone,
  onClick,
  active,
}: {
  label: string;
  value: number;
  tone?: "warn" | "ok";
  onClick?: () => void;
  active?: boolean;
}) {
  const content = (
    <>
      <p className="text-[11px] font-medium text-muted">
        {label}
        {onClick && (
          <span className="ml-2 text-fuchsia-600">
            {active ? "Clear filter ↗" : "View ↗"}
          </span>
        )}
      </p>
      <p
        className={`mt-1 text-2xl font-semibold ${tone === "warn" ? "text-amber-600" : tone === "ok" ? "text-emerald-600" : "text-ink"}`}
      >
        {value}
      </p>
    </>
  );
  const className = `rounded-2xl border bg-white p-5 text-left shadow-sm transition ${active ? "border-fuchsia-400 ring-2 ring-fuchsia-100" : "border-line"}`;
  return onClick ? (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={!!active}
      className={`${className} hover:border-fuchsia-300`}
    >
      {content}
    </button>
  ) : (
    <div className={className}>{content}</div>
  );
}

function Badge({
  tone,
  children,
}: {
  tone: "ok" | "warn" | "danger" | "neutral";
  children: React.ReactNode;
}) {
  const styles =
    tone === "ok"
      ? "bg-emerald-50 text-emerald-700"
      : tone === "warn"
        ? "bg-amber-50 text-amber-700"
        : tone === "danger"
          ? "bg-red-50 text-rydr-red"
          : "bg-grouped text-muted";
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${styles}`}
    >
      {children}
    </span>
  );
}
