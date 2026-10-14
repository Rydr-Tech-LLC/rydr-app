"use client";
import { vehicleImageSearchUrl } from "@/lib/vehicleImageSearch";

import VehicleSpecificationFields from "@/components/VehicleSpecificationFields";
import { useState } from "react";
import { useRouter } from "next/navigation";

const BODY_STYLES = ["sedan", "suv", "truck", "coupe", "hatchback", "minivan", "crossover", "wagon", "convertible", "van", "unknown"];
const RIDE_TYPES = ["Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine"];

export default function NewVehicleForm() {
  const router = useRouter();
  const [make, setMake] = useState("");
  const [model, setModel] = useState("");
  const [yearStart, setYearStart] = useState("");
  const [yearEnd, setYearEnd] = useState("");
  const [trim, setTrim] = useState("");
  const [bodyStyle, setBodyStyle] = useState("sedan");
  const [specifications, setSpecifications] = useState<any>({});
  const [eligibleRideTypes, setEligibleRideTypes] = useState<string[]>(["Rydr Go"]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggleRideType(rideType: string) {
    setEligibleRideTypes((current) =>
      current.includes(rideType) ? current.filter((value) => value !== rideType) : [...current, rideType]
    );
  }

  async function submit() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/vehicle-library", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          make,
          model,
          yearStart: Number(yearStart),
          yearEnd: Number(yearEnd || yearStart),
          trim: trim || undefined,
          bodyStyle,
          eligibleRideTypes,
          specifications
        })
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Could not create entry.");
        return;
      }
      router.push(`/vehicle-library/${body.entry.vehicleId}`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-5 rounded-3xl border border-line bg-white p-6 shadow-sm">
      <h2 className="text-lg font-semibold text-ink">1. Match the vehicle</h2>
      <p className="text-sm text-muted">Use the manufacturer as the make, and the vehicle name as the model. These details match the VIN decoder.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Make">
          <input value={make} onChange={(e) => setMake(e.target.value)} placeholder="e.g. Land Rover" className={inputClass} />
        </Field>
        <Field label="Model">
          <input value={model} onChange={(e) => setModel(e.target.value)} placeholder="e.g. Range Rover Sport" className={inputClass} />
        </Field>
        <Field label="Year start">
          <input value={yearStart} onChange={(e) => setYearStart(e.target.value)} inputMode="numeric" placeholder="First model year" className={inputClass} />
        </Field>
        <Field label="Year end">
          <input value={yearEnd} onChange={(e) => setYearEnd(e.target.value)} inputMode="numeric" placeholder="Same if exact year" className={inputClass} />
        </Field>
        <Field label="Trim">
          <input value={trim} onChange={(e) => setTrim(e.target.value)} placeholder="Optional trim or generation" className={inputClass} />
        </Field>
        <Field label="Body style">
          <select value={bodyStyle} onChange={(e) => setBodyStyle(e.target.value)} className={inputClass}>
            {BODY_STYLES.map((style) => (
              <option key={style} value={style}>
                {style}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <h2 className="border-t border-line pt-5 text-lg font-semibold text-ink">2. Verify seating and classification</h2>
      <VehicleSpecificationFields value={specifications} onChange={setSpecifications} />

      <div>
        <h2 className="mb-3 text-lg font-semibold text-ink">3. Choose ride eligibility</h2>
        <div className="grid gap-2 sm:grid-cols-3">
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
        <p className="mt-2 text-[11px] text-muted">
          Leave blank only when the vehicle should require manual eligibility review.
        </p>
      </div>

      <div className="rounded-md border border-line bg-grouped p-3 text-[11px] text-muted">
        <p className="font-medium text-ink">How this entry is used</p>
        <p className="mt-1">
          During driver onboarding, the app matches make, model, year, trim, and color against this library. If a color
          image exists, that image becomes the driver's generic vehicle image. Otherwise the default image or fallback
          entries are used.
        </p>
        <a
          href={vehicleImageSearchUrl({ make, model, yearStart, trim })}
          target="_blank"
          rel="noreferrer"
          className="mt-3 inline-flex rounded-md border border-rydr-burgundy px-3 py-1.5 text-xs font-semibold text-rydr-burgundy hover:bg-red-50"
        >
          Search Google Images
        </a>
      </div>

      {error && <p className="text-xs text-rydr-red">{error}</p>}

      <button
        onClick={submit}
        disabled={loading || !make || !model || !yearStart}
        className="w-full rounded-xl bg-gradient-to-r from-red-500 via-fuchsia-600 to-blue-600 py-2 text-xs font-semibold text-white disabled:opacity-40"
      >
        {loading ? "Creating…" : "Create vehicle → Add images"}
      </button>
    </div>
  );
}

const inputClass = "w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-fuchsia-500 focus:ring-2 focus:ring-fuchsia-100";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}
