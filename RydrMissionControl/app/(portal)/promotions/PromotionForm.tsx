"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export interface PromotionFormInitial {
  id?: string;
  title?: string;
  description?: string | null;
  status?: string;
  type?: string;
  appliesTo?: string;
  startsAt?: string;
  endsAt?: string;
  timezone?: string;
  markets?: string[];
  rideTypes?: string[];
  discountKind?: string | null;
  discountPercent?: number | null;
  discountCents?: number | null;
  maxDiscountCents?: number | null;
  bonusCents?: number | null;
  milestoneRideCount?: number | null;
  rewardKind?: string | null;
  rewardQuantity?: number | null;
  rewardCents?: number | null;
  maxRedemptions?: number | null;
  perUserLimit?: number | null;
  betaOnly?: boolean;
}

const STATUSES = ["draft", "scheduled", "active", "paused", "ended"];
const TYPES = [
  ["rider_fare_discount", "Rider fare discount"],
  ["driver_per_ride_bonus", "Driver per-ride bonus"],
  ["driver_milestone_reward", "Driver milestone reward"]
];
const APPLIES_TO = [
  ["normalRydr", "Normal Rydr"],
  ["cashHub", "Cash Hub"],
  ["both", "Both"]
];

export default function PromotionForm({ initial }: { initial?: PromotionFormInitial }) {
  const router = useRouter();
  const [title, setTitle] = useState(initial?.title ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [status, setStatus] = useState(initial?.status ?? "draft");
  const [type, setType] = useState(initial?.type ?? "rider_fare_discount");
  const [appliesTo, setAppliesTo] = useState(initial?.appliesTo ?? "normalRydr");
  const [startsAt, setStartsAt] = useState(toDateTimeLocal(initial?.startsAt));
  const [endsAt, setEndsAt] = useState(toDateTimeLocal(initial?.endsAt));
  const [timezone, setTimezone] = useState(initial?.timezone ?? "America/New_York");
  const [markets, setMarkets] = useState((initial?.markets ?? []).join(", "));
  const [rideTypes, setRideTypes] = useState((initial?.rideTypes ?? []).join(", "));
  const [discountKind, setDiscountKind] = useState(initial?.discountKind ?? "percent");
  const [discountPercent, setDiscountPercent] = useState(String(initial?.discountPercent ?? 50));
  const [discountDollars, setDiscountDollars] = useState(centsToDollars(initial?.discountCents));
  const [maxDiscountDollars, setMaxDiscountDollars] = useState(centsToDollars(initial?.maxDiscountCents));
  const [bonusDollars, setBonusDollars] = useState(centsToDollars(initial?.bonusCents ?? 200));
  const [milestoneRideCount, setMilestoneRideCount] = useState(String(initial?.milestoneRideCount ?? 2));
  const [rewardKind, setRewardKind] = useState(initial?.rewardKind ?? "rydr_bank_credit");
  const [rewardQuantity, setRewardQuantity] = useState(String(initial?.rewardQuantity ?? 1));
  const [rewardDollars, setRewardDollars] = useState(centsToDollars(initial?.rewardCents));
  const [maxRedemptions, setMaxRedemptions] = useState(String(initial?.maxRedemptions ?? ""));
  const [perUserLimit, setPerUserLimit] = useState(String(initial?.perUserLimit ?? ""));
  const [betaOnly, setBetaOnly] = useState(initial?.betaOnly === true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setSaving(true);
    setError(null);
    try {
      const payload = {
        title,
        description,
        status,
        type,
        appliesTo,
        startsAt: new Date(startsAt).toISOString(),
        endsAt: new Date(endsAt).toISOString(),
        timezone,
        markets,
        rideTypes,
        discountKind,
        discountPercent: numberOrNull(discountPercent),
        discountCents: dollarsToCents(discountDollars),
        maxDiscountCents: dollarsToCents(maxDiscountDollars),
        bonusCents: dollarsToCents(bonusDollars),
        milestoneRideCount: numberOrNull(milestoneRideCount),
        rewardKind,
        rewardQuantity: numberOrNull(rewardQuantity),
        rewardCents: dollarsToCents(rewardDollars),
        maxRedemptions: numberOrNull(maxRedemptions),
        perUserLimit: numberOrNull(perUserLimit),
        betaOnly
      };
      const res = await fetch(initial?.id ? `/api/promotions/${initial.id}` : "/api/promotions", {
        method: initial?.id ? "PATCH" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Promotion could not be saved.");
        return;
      }
      router.push(`/promotions/${initial?.id ?? body.id}`);
      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="grid gap-4 lg:grid-cols-3">
        <Field label="Title">
          <input value={title} onChange={(event) => setTitle(event.target.value)} className={inputClass} placeholder="July afternoon 50% off" />
        </Field>
        <Field label="Type">
          <select value={type} onChange={(event) => setType(event.target.value)} className={inputClass}>
            {TYPES.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Status">
          <select value={status} onChange={(event) => setStatus(event.target.value)} className={inputClass}>
            {STATUSES.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Starts">
          <input type="datetime-local" value={startsAt} onChange={(event) => setStartsAt(event.target.value)} className={inputClass} />
        </Field>
        <Field label="Ends">
          <input type="datetime-local" value={endsAt} onChange={(event) => setEndsAt(event.target.value)} className={inputClass} />
        </Field>
        <Field label="Timezone">
          <input value={timezone} onChange={(event) => setTimezone(event.target.value)} className={inputClass} />
        </Field>
        <Field label="Applies to">
          <select value={appliesTo} onChange={(event) => setAppliesTo(event.target.value)} className={inputClass}>
            {APPLIES_TO.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Markets">
          <input value={markets} onChange={(event) => setMarkets(event.target.value)} className={inputClass} placeholder="ATL, NYC, NJ" />
        </Field>
        <Field label="Ride types">
          <input value={rideTypes} onChange={(event) => setRideTypes(event.target.value)} className={inputClass} placeholder="Rydr Go, Rydr XL" />
        </Field>
      </div>

      <div className="mt-4">
        <Field label="Description">
          <textarea value={description} onChange={(event) => setDescription(event.target.value)} className={`${inputClass} min-h-20`} />
        </Field>
      </div>

      {type === "rider_fare_discount" && (
        <div className="mt-4 grid gap-4 rounded-md border border-line bg-grouped p-4 lg:grid-cols-4">
          <Field label="Discount kind">
            <select value={discountKind} onChange={(event) => setDiscountKind(event.target.value)} className={inputClass}>
              <option value="percent">Percent</option>
              <option value="fixed">Fixed amount</option>
            </select>
          </Field>
          <Field label="Discount percent">
            <input value={discountPercent} onChange={(event) => setDiscountPercent(event.target.value)} inputMode="numeric" className={inputClass} />
          </Field>
          <Field label="Fixed discount dollars">
            <input value={discountDollars} onChange={(event) => setDiscountDollars(event.target.value)} inputMode="decimal" className={inputClass} />
          </Field>
          <Field label="Max discount dollars">
            <input value={maxDiscountDollars} onChange={(event) => setMaxDiscountDollars(event.target.value)} inputMode="decimal" className={inputClass} />
          </Field>
        </div>
      )}

      {type === "driver_per_ride_bonus" && (
        <div className="mt-4 grid gap-4 rounded-md border border-line bg-grouped p-4 lg:grid-cols-3">
          <Field label="Bonus dollars per ride">
            <input value={bonusDollars} onChange={(event) => setBonusDollars(event.target.value)} inputMode="decimal" className={inputClass} />
          </Field>
        </div>
      )}

      {type === "driver_milestone_reward" && (
        <div className="mt-4 grid gap-4 rounded-md border border-line bg-grouped p-4 lg:grid-cols-4">
          <Field label="Eligible rides required">
            <input value={milestoneRideCount} onChange={(event) => setMilestoneRideCount(event.target.value)} inputMode="numeric" className={inputClass} />
          </Field>
          <Field label="Reward kind">
            <select value={rewardKind} onChange={(event) => setRewardKind(event.target.value)} className={inputClass}>
              <option value="rydr_bank_credit">Rydr Bank credit</option>
              <option value="cash_bonus">Cash bonus</option>
            </select>
          </Field>
          <Field label="Credit quantity">
            <input value={rewardQuantity} onChange={(event) => setRewardQuantity(event.target.value)} inputMode="numeric" className={inputClass} />
          </Field>
          <Field label="Cash reward dollars">
            <input value={rewardDollars} onChange={(event) => setRewardDollars(event.target.value)} inputMode="decimal" className={inputClass} />
          </Field>
        </div>
      )}

      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <Field label="Max total redemptions">
          <input value={maxRedemptions} onChange={(event) => setMaxRedemptions(event.target.value)} inputMode="numeric" className={inputClass} />
        </Field>
        <Field label="Per-user limit">
          <input value={perUserLimit} onChange={(event) => setPerUserLimit(event.target.value)} inputMode="numeric" className={inputClass} />
        </Field>
        <label className="flex items-center gap-2 self-end rounded-md border border-line bg-grouped px-3 py-2 text-xs font-semibold text-ink">
          <input type="checkbox" checked={betaOnly} onChange={(event) => setBetaOnly(event.target.checked)} className="h-4 w-4" />
          Beta-only eligibility
        </label>
      </div>

      {error && <p className="mt-4 text-xs text-rydr-red">{error}</p>}

      <button
        onClick={submit}
        disabled={saving || !title.trim() || !startsAt || !endsAt}
        className="mt-5 rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-40"
      >
        {saving ? "Saving" : initial?.id ? "Save Promotion" : "Create Promotion"}
      </button>
    </section>
  );
}

const inputClass = "w-full rounded-md border border-line bg-white px-3 py-2 text-xs outline-none focus:border-ink";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-[11px] font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}

function toDateTimeLocal(value?: string) {
  const date = value ? new Date(value) : new Date(Date.now() + 60 * 60 * 1000);
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function centsToDollars(value?: number | null) {
  if (!value) return "";
  return (value / 100).toFixed(2);
}

function dollarsToCents(value: string) {
  if (!value.trim()) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.round(parsed * 100) : null;
}

function numberOrNull(value: string) {
  if (!value.trim()) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}
