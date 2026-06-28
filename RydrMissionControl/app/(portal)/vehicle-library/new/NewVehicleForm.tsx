"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

const BODY_STYLES = ["sedan", "suv", "truck", "coupe", "hatchback", "minivan", "crossover", "wagon", "convertible", "van", "unknown"];

const GENERIC_PRESETS = [
  { label: "Generic make placeholder (any model of a make)", make: "_generic_make", hint: "Set make to e.g. _generic_make_toyota and model to \"Generic\"." },
  { label: "Generic body-style placeholder (system floor)", make: "_generic_body", hint: "Set make to e.g. _generic_body_sedan and model to \"Generic\"." }
];

export default function NewVehicleForm() {
  const router = useRouter();
  const [make, setMake] = useState("");
  const [model, setModel] = useState("");
  const [yearStart, setYearStart] = useState("");
  const [yearEnd, setYearEnd] = useState("");
  const [trim, setTrim] = useState("");
  const [bodyStyle, setBodyStyle] = useState("sedan");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
          bodyStyle
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
    <div className="space-y-4 rounded-lg border border-line bg-white p-5 shadow-sm">
      <Field label="Make">
        <input value={make} onChange={(e) => setMake(e.target.value)} placeholder="Toyota" className={inputClass} />
      </Field>
      <Field label="Model">
        <input value={model} onChange={(e) => setModel(e.target.value)} placeholder="Camry" className={inputClass} />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Year start">
          <input value={yearStart} onChange={(e) => setYearStart(e.target.value)} placeholder="2018" className={inputClass} />
        </Field>
        <Field label="Year end">
          <input value={yearEnd} onChange={(e) => setYearEnd(e.target.value)} placeholder="2024" className={inputClass} />
        </Field>
      </div>
      <Field label="Trim (optional)">
        <input value={trim} onChange={(e) => setTrim(e.target.value)} placeholder="LE" className={inputClass} />
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

      <div className="rounded-md bg-grouped p-3 text-[11px] text-muted">
        <p className="font-medium text-ink">Adding a fallback / generic placeholder instead?</p>
        {GENERIC_PRESETS.map((preset) => (
          <p key={preset.label} className="mt-1">
            <span className="font-medium">{preset.label}:</span> {preset.hint}
          </p>
        ))}
      </div>

      {error && <p className="text-xs text-rydr-red">{error}</p>}

      <button
        onClick={submit}
        disabled={loading || !make || !model || !yearStart}
        className="w-full rounded-md bg-ink py-2 text-xs font-semibold text-white disabled:opacity-40"
      >
        {loading ? "Creating…" : "Create Entry"}
      </button>
    </div>
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
