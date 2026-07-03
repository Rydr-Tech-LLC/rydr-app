"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { VehicleBodyStyle, VehicleLibraryEntry } from "@/lib/vehicleLibrary";

const BODY_STYLES: VehicleBodyStyle[] = ["sedan", "suv", "truck", "coupe", "hatchback", "minivan", "crossover", "wagon", "convertible", "van", "unknown"];
const RIDE_TYPES = ["Rydr Go", "Rydr Eco", "Rydr XL"];

export default function VehicleMetadataEditor({ entry }: { entry: VehicleLibraryEntry }) {
  const router = useRouter();
  const [make, setMake] = useState(entry.make);
  const [model, setModel] = useState(entry.model);
  const [yearStart, setYearStart] = useState(String(entry.yearStart));
  const [yearEnd, setYearEnd] = useState(String(entry.yearEnd));
  const [trim, setTrim] = useState(entry.trim ?? "");
  const [bodyStyle, setBodyStyle] = useState(entry.bodyStyle);
  const [eligibleRideTypes, setEligibleRideTypes] = useState<string[]>(entry.eligibleRideTypes ?? []);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function toggleRideType(rideType: string) {
    setEligibleRideTypes((current) =>
      current.includes(rideType) ? current.filter((value) => value !== rideType) : [...current, rideType]
    );
  }

  async function save() {
    setSaving(true);
    setMessage(null);
    setError(null);
    try {
      const res = await fetch(`/api/vehicle-library/${entry.vehicleId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          make,
          model,
          yearStart: Number(yearStart),
          yearEnd: Number(yearEnd),
          trim,
          bodyStyle,
          eligibleRideTypes
        })
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Vehicle metadata could not be saved.");
        return;
      }
      setMessage("Saved.");
      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-ink">Vehicle Matching</h2>
          <p className="mt-1 text-xs text-muted">
            These fields decide which driver vehicles match this image set during onboarding.
          </p>
        </div>
        <button
          onClick={save}
          disabled={saving || !make.trim() || !model.trim() || !yearStart.trim()}
          className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-40"
        >
          {saving ? "Saving" : "Save"}
        </button>
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-3">
        <Field label="Make">
          <input value={make} onChange={(event) => setMake(event.target.value)} className={inputClass} />
        </Field>
        <Field label="Model">
          <input value={model} onChange={(event) => setModel(event.target.value)} className={inputClass} />
        </Field>
        <Field label="Trim">
          <input value={trim} onChange={(event) => setTrim(event.target.value)} placeholder="Optional" className={inputClass} />
        </Field>
        <Field label="Year start">
          <input value={yearStart} onChange={(event) => setYearStart(event.target.value)} inputMode="numeric" className={inputClass} />
        </Field>
        <Field label="Year end">
          <input value={yearEnd} onChange={(event) => setYearEnd(event.target.value)} inputMode="numeric" className={inputClass} />
        </Field>
        <Field label="Body style">
          <select value={bodyStyle} onChange={(event) => setBodyStyle(event.target.value as VehicleBodyStyle)} className={inputClass}>
            {BODY_STYLES.map((style) => (
              <option key={style} value={style}>
                {style}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <div className="mt-4">
        <p className="mb-2 text-[11px] font-medium text-muted">Ride type eligibility</p>
        <div className="grid gap-2 md:grid-cols-3">
          {RIDE_TYPES.map((rideType) => (
            <label
              key={rideType}
              className={`flex cursor-pointer items-center justify-between rounded-md border px-3 py-2 text-xs font-semibold ${
                eligibleRideTypes.includes(rideType) ? "border-rydr-burgundy bg-red-50 text-ink" : "border-line bg-grouped text-muted"
              }`}
            >
              <span>{rideType}</span>
              <input
                type="checkbox"
                checked={eligibleRideTypes.includes(rideType)}
                onChange={() => toggleRideType(rideType)}
                className="h-4 w-4"
              />
            </label>
          ))}
        </div>
      </div>

      {message && <p className="mt-3 text-xs text-emerald-700">{message}</p>}
      {error && <p className="mt-3 text-xs text-rydr-red">{error}</p>}
    </section>
  );
}

const inputClass = "w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-1 text-[11px] font-medium text-muted">{label}</p>
      {children}
    </div>
  );
}
