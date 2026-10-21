"use client";
import {useWorkspaceRouter as useRouter} from "@/components/WorkspaceContext";

import { useState } from "react";
import {
  normalizeMechanics,
  validateOffer,
  localTimeToISO,
} from "@/lib/promotionPolicy";


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
  schemaVersion?: number;
  applicationMode?: string;
  promoCode?: string | null;
  audienceRule?: string;
  audienceUserIds?: string[];
  limitKind?: string;
  maxDistanceMiles?: number | null;
  rewardExpiresAfterDays?: number;
  payExcessFare?: boolean;
}
const inputClass =
  "w-full rounded-xl border border-line bg-white px-3 py-2.5 text-sm outline-none focus:border-fuchsia-500 focus:ring-2 focus:ring-fuchsia-100";
const gradient = "bg-gradient-to-r from-red-500 via-fuchsia-600 to-blue-600";
const dollars = (v?: number | null) => (v == null ? "" : (v / 100).toFixed(2));
const cents = (v: string) => (v.trim() ? Math.round(Number(v) * 100) : null);
function eastern(value?: string) {
  const date = new Date(value ?? Date.now());
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(date)
      .map((x) => [x.type, x.value]),
  );
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}

export default function PromotionForm({
  initial,
}: {
  initial?: PromotionFormInitial;
}) {
  const router = useRouter();
  const [f, setF] = useState({
    title: initial?.title ?? "",
    description: initial?.description ?? "",
    audience: initial?.type?.startsWith("driver_") ? "drivers" : "riders",
    type: initial?.type ?? "rider_fare_discount",
    discountKind: initial?.discountKind ?? "percent",
    percent: String(initial?.discountPercent ?? 20),
    discount: dollars(initial?.discountCents ?? 500),
    maxDiscount: dollars(initial?.id ? initial.maxDiscountCents : 2500),
    bonus: dollars(initial?.bonusCents ?? 200),
    milestone: String(initial?.milestoneRideCount ?? 2),
    rewardKind: initial?.rewardKind ?? "free_ride",
    reward: dollars(initial?.rewardCents ?? 1000),
    applicationMode: initial?.applicationMode ?? "automatic",
    promoCode: initial?.promoCode ?? "",
    audienceRule: initial?.audienceRule ?? (initial?.betaOnly ? "beta" : "all"),
    audienceUserIds: (initial?.audienceUserIds ?? []).join(", "),
    markets: initial?.markets ?? [],
    rideTypes: initial?.rideTypes ?? [],
    limitKind: initial?.limitKind ?? "distance",
    miles: String(initial?.maxDistanceMiles ?? 10),
    expires: String(initial?.rewardExpiresAfterDays ?? 30),
    payExcess: initial?.payExcessFare !== false,
    perUser: initial?.id ? String(initial.perUserLimit ?? (initial.audienceRule === "new" ? 1 : "")) : "1",
    total: initial?.id ? String(initial.maxRedemptions ?? "") : "500",
    startNow: !initial?.id,
    starts: eastern(initial?.startsAt),
    ends: eastern(
      initial?.endsAt ?? new Date(Date.now() + 30 * 86400000).toISOString(),
    ),
  });
  const [activeStep, setActiveStep] = useState(0),
    [selectedPreset, setSelectedPreset] = useState("custom");
  const [review, setReview] = useState(false),
    [saving, setSaving] = useState(false),
    [error, setError] = useState("");
  function update<K extends keyof typeof f>(key: K, value: (typeof f)[K]) {
    setF((old) => ({ ...old, [key]: value }));
    setReview(false);
    setActiveStep(0);
    setSelectedPreset("custom");
  }
  function chooseAudience(audience: string) {
    setF((old) => ({
      ...old,
      audience,
      type:
        audience === "drivers"
          ? "driver_per_ride_bonus"
          : "rider_fare_discount",
      rewardKind: audience === "drivers" ? "cash_bonus" : "free_ride",
      limitKind: audience === "drivers" ? "amount" : "distance",
      perUser: audience === "drivers" ? "" : "1",
    }));
    setReview(false);
  }
  function preset(rides: number) {
    setF((old) => ({
      ...old,
      type:
        old.audience === "drivers"
          ? "driver_milestone_reward"
          : "rider_milestone_reward",
      milestone: String(rides),
      perUser: "1",
      rewardKind: old.audience === "drivers" ? "cash_bonus" : "free_ride",
    }));
    setReview(false);
    setSelectedPreset(String(rides));
  }
  function toggle(key: "markets" | "rideTypes", value: string) {
    update(
      key,
      f[key].includes(value)
        ? f[key].filter((x) => x !== value)
        : [...f[key], value],
    );
  }
  const driver = f.audience === "drivers",
    milestone = f.type.endsWith("milestone_reward");
  const free =
    !driver &&
    (milestone ? f.rewardKind === "free_ride" : f.discountKind === "free_ride");
  const offer = driver
    ? milestone
      ? `Complete ${f.milestone} rides, earn $${f.reward}`
      : `Earn $${f.bonus} extra per ride`
    : milestone
      ? `Complete ${f.milestone} paid rides, unlock ${free ? "a free ride" : `$${f.reward} ride credit`}`
      : free
        ? "Your next ride is covered"
        : f.discountKind === "percent"
          ? `${f.percent}% off your ride`
          : `$${f.discount} off your ride`;
  const limit = free
    ? f.limitKind === "distance"
      ? `Up to ${f.miles} miles`
      : `Up to $${f.maxDiscount}`
    : "";
  let validationIssue = "";
  try {
    const candidate = {
      type: f.type,
      appliesTo: "normalRydr",
      discountKind: f.discountKind,
      discountPercent: Number(f.percent),
      discountCents: cents(f.discount),
      bonusCents: cents(f.bonus),
      milestoneRideCount: Number(f.milestone),
      rewardKind: driver ? "cash_bonus" : f.rewardKind,
      rewardCents: cents(f.reward),
      maxDiscountCents: free
        ? f.limitKind === "distance"
          ? null
          : cents(f.maxDiscount)
        : !driver && !milestone && f.discountKind === "percent"
          ? cents(f.maxDiscount)
          : null,
      perUserLimit: f.perUser ? Number(f.perUser) : null,
      maxRedemptions: f.total ? Number(f.total) : null,
      applicationMode: f.applicationMode,
      promoCode: f.promoCode,
      audienceRule: f.audienceRule,
      audienceUserIds: f.audienceUserIds.split(",").filter((x) => x.trim()),
      limitKind: free ? f.limitKind : "amount",
      maxDistanceMiles: Number(f.miles),
      rewardExpiresAfterDays: Number(f.expires),
    };
    validateOffer({ ...candidate, ...normalizeMechanics(candidate, "active") });
    const start = f.startNow
      ? Date.now()
      : Date.parse(localTimeToISO(f.starts));
    const end = Date.parse(localTimeToISO(f.ends));
    if (end <= start || end <= Date.now())
      validationIssue = "End date must be after the start and in the future.";
  } catch (e) {
    validationIssue = e instanceof Error ? e.message : "Complete the offer.";
  }
  const ready =
    !validationIssue &&
    !!f.title.trim() &&
    !!f.ends &&
    (f.applicationMode !== "code" ||
      /^[A-Z0-9][A-Z0-9_-]{2,31}$/.test(f.promoCode)) &&
    (f.audienceRule !== "specific" || !!f.audienceUserIds.trim());
  async function submit(draft: boolean) {
    setSaving(true);
    setError("");
    try {
      const status = draft ? "draft" : f.startNow ? "active" : "scheduled";
      const payload = {
        schemaVersion: 2,
        title: f.title,
        description: f.description,
        type: f.type,
        status,
        appliesTo: "normalRydr",
        startsLocal: f.starts,
        endsLocal: f.ends,
        startNow: f.startNow,
        timezone: "America/New_York",
        markets: f.markets,
        rideTypes: f.rideTypes,
        discountKind: f.discountKind,
        discountPercent: Number(f.percent),
        discountCents: cents(f.discount),
        maxDiscountCents: free
          ? f.limitKind === "distance"
            ? null
            : cents(f.maxDiscount)
          : !driver && !milestone && f.discountKind === "percent"
            ? cents(f.maxDiscount)
            : null,
        bonusCents: cents(f.bonus),
        milestoneRideCount: Number(f.milestone),
        rewardKind: driver ? "cash_bonus" : f.rewardKind,
        rewardCents: cents(f.reward),
        applicationMode: f.applicationMode,
        promoCode: f.promoCode,
        audienceRule: f.audienceRule,
        audienceUserIds: f.audienceUserIds
          .split(",")
          .map((x) => x.trim())
          .filter(Boolean),
        limitKind: free ? f.limitKind : "amount",
        maxDistanceMiles: Number(f.miles),
        rewardExpiresAfterDays: Number(f.expires),
        payExcessFare: f.payExcess,
        perUserLimit: f.perUser ? Number(f.perUser) : null,
        maxRedemptions: f.total ? Number(f.total) : null,
      };
      const res = await fetch(
        initial?.id ? `/api/promotions/${initial.id}` : "/api/promotions",
        {
          method: initial?.id ? "PATCH" : "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        },
      );
      const body = await res.json();
      if (!res.ok) throw Error(body.error ?? "Could not save promotion.");
      router.push(`/promotions/${initial?.id ?? body.id}`);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save promotion.");
    } finally {
      setSaving(false);
    }
  }
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="inline-flex rounded-full border border-line bg-white p-1">
          {["riders", "drivers"].map((a) => (
            <button
              key={a}
              type="button"
              aria-pressed={f.audience === a}
              onClick={() => chooseAudience(a)}
              className={`rounded-full px-6 py-2 text-sm font-semibold transition ${f.audience === a ? `${gradient} text-white shadow-sm` : "text-muted hover:bg-grouped"}`}
            >
              {a === "riders" ? "Rider promotions" : "Driver promotions"}
            </button>
          ))}
        </div>
        <button
          type="button"
          disabled={saving}
          onClick={() => submit(true)}
          className="rounded-xl border border-line bg-white px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
        >
          {saving
            ? "Saving…"
            : initial?.status && initial.status !== "draft"
              ? "Save as draft"
              : "Save draft"}
        </button>
      </div>
      {initial?.schemaVersion !== 2 && initial?.id && (
        <p className="rounded-xl bg-amber-50 p-4 text-sm text-amber-800">
          Saving upgrades this campaign to the new promotion mechanics. Existing
          reward records stay available. Driver milestone rewards now use cash
          bonuses.
        </p>
      )}
      <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_340px]">
        <div className="rounded-3xl border border-line bg-white p-5 shadow-sm sm:p-7">
          <nav aria-label="Promotion steps" className="mb-7 flex gap-2">
            {["Offer", "Eligibility", "Schedule", "Review"].map((s, i) => (
              <button
                key={s}
                type="button"
                onClick={() => {
                  setActiveStep(i);
                  if (i === 3) setReview(true);
                  else {
                    setReview(false);
                    document
                      .getElementById(`promotion-${i}`)
                      ?.scrollIntoView({ behavior: "smooth", block: "start" });
                  }
                }}
                className={`flex-1 rounded-xl px-2 py-2 text-xs font-semibold ${activeStep === i ? "bg-red-50 text-rydr-red" : "bg-grouped text-muted"}`}
              >
                {i + 1}. {s}
              </button>
            ))}
          </nav>
          {review ? (
            <div className="space-y-5">
              <h2 className="text-xl font-semibold">
                Review before publishing
              </h2>
              <p className="text-sm text-muted">
                {offer}. {limit}.
              </p>
              <dl className="grid gap-4 text-sm sm:grid-cols-2">
                <Summary label="Campaign" value={f.title || "Add a title"} />
                <Summary
                  label="Audience"
                  value={`${f.audienceRule} ${f.audience}`}
                />
                <Summary
                  label="Applied"
                  value={
                    f.applicationMode === "code"
                      ? `Code: ${f.promoCode}`
                      : "Automatically"
                  }
                />
                <Summary
                  label="Markets"
                  value={f.markets.join(", ") || "All markets"}
                />
                <Summary
                  label="Ride types"
                  value={f.rideTypes.join(", ") || "All eligible ride types"}
                />
                <Summary
                  label="Limits"
                  value={`${f.perUser || (f.audienceRule === "new" ? "1" : "Unlimited")} per account · ${f.total || "Unlimited"} total`}
                />
                <Summary
                  label="Starts"
                  value={
                    f.startNow
                      ? "On publication"
                      : `${f.starts.replace("T", " ")} ET`
                  }
                />
                <Summary
                  label="Ends"
                  value={`${f.ends.replace("T", " ")} ET`}
                />
              </dl>
              <p className="rounded-xl bg-blue-50 p-4 text-sm text-blue-800">
                {driver
                  ? "Bonuses are funded by Rydr and added to normal earnings. Payout failures appear in Mission Control."
                  : "Rydr funds the discount. Drivers keep their full-fare earnings. Tips, tolls, wait charges and other extras remain payable."}
              </p>
              <button
                type="button"
                onClick={() => {
                  setReview(false);
                  setActiveStep(0);
                }}
                className="text-sm font-semibold text-fuchsia-700"
              >
                ← Edit details
              </button>
            </div>
          ) : (
            <div className="space-y-7">
              <section id="promotion-0" className="scroll-mt-5 space-y-4">
                <Heading
                  n={1}
                  title={
                    driver
                      ? "What should drivers earn?"
                      : "What should riders receive?"
                  }
                />
                <div
                  className={`grid gap-3 ${driver ? "sm:grid-cols-2" : "sm:grid-cols-2 2xl:grid-cols-4"}`}
                >
                  {(driver
                    ? [
                        [
                          "driver_per_ride_bonus",
                          "cash_bonus",
                          "Per-ride bonus",
                          "Add cash to every qualifying ride.",
                        ],
                        [
                          "driver_milestone_reward",
                          "cash_bonus",
                          "Ride milestone",
                          "Reward a completed ride goal.",
                        ],
                      ]
                    : [
                        [
                          "rider_fare_discount",
                          "percent",
                          "Percentage off",
                          "Discount an eligible ride.",
                        ],
                        [
                          "rider_fare_discount",
                          "fixed",
                          "Dollar amount off",
                          "Offer a fixed fare credit.",
                        ],
                        [
                          "rider_fare_discount",
                          "free_ride",
                          "Free ride credit",
                          "Cover a ride within your limit.",
                        ],
                        [
                          "rider_milestone_reward",
                          "free_ride",
                          "Ride milestone",
                          "Unlock a reward after paid rides.",
                        ],
                      ]
                  ).map(([type, kind, label, detail]) => (
                    <Choice
                      key={label}
                      selected={
                        f.type === type &&
                        (driver || milestone || f.discountKind === kind)
                      }
                      label={label}
                      detail={detail}
                      onClick={() => {
                        update("type", type);
                        if (!driver) update("discountKind", kind);
                      }}
                    />
                  ))}
                </div>
                <p className="text-xs font-medium text-muted">
                  Choose a suggestion, then make it yours
                </p>
                <div className="grid gap-2 sm:grid-cols-3">
                  <Choice
                    selected={selectedPreset === String(driver ? 10 : 1)}
                    label={
                      driver
                        ? "Complete 10 rides → bonus"
                        : "First ride → next ride free"
                    }
                    onClick={() => preset(driver ? 10 : 1)}
                  />
                  <Choice
                    selected={selectedPreset === String(driver ? 25 : 2)}
                    label={
                      driver
                        ? "Complete 25 rides → bonus"
                        : "Complete 2 rides → next free"
                    }
                    onClick={() => preset(driver ? 25 : 2)}
                  />
                  <Choice
                    selected={selectedPreset === "custom"}
                    label="Build custom"
                    onClick={() => update("milestone", f.milestone)}
                  />
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Promotion title">
                    <input
                      className={inputClass}
                      value={f.title}
                      onChange={(e) => update("title", e.target.value)}
                      placeholder={
                        driver
                          ? "Your next earning milestone"
                          : "Your next ride, on Rydr"
                      }
                    />
                  </Field>
                  <Field label="Message shown to users">
                    <input
                      className={inputClass}
                      value={f.description}
                      onChange={(e) => update("description", e.target.value)}
                      placeholder="Write your offer in your own words"
                    />
                  </Field>
                </div>
                <div className="grid gap-4 rounded-2xl bg-gradient-to-br from-red-50 to-fuchsia-50 p-4 sm:grid-cols-2">
                  {milestone && (
                    <Field label="Qualifying completed rides">
                      <input
                        type="number"
                        min={1}
                        className={inputClass}
                        value={f.milestone}
                        onChange={(e) => update("milestone", e.target.value)}
                      />
                    </Field>
                  )}
                  {!driver && milestone && (
                    <Field label="Reward">
                      <select
                        className={inputClass}
                        value={f.rewardKind}
                        onChange={(e) => update("rewardKind", e.target.value)}
                      >
                        <option value="free_ride">
                          A free ride within limits
                        </option>
                        <option value="fixed">Fare credit</option>
                      </select>
                    </Field>
                  )}
                  {driver && (
                    <Field
                      label={
                        milestone ? "Cash bonus ($)" : "Bonus per ride ($)"
                      }
                    >
                      <input
                        type="number"
                        min="0.01"
                        step="0.01"
                        className={inputClass}
                        value={milestone ? f.reward : f.bonus}
                        onChange={(e) =>
                          update(milestone ? "reward" : "bonus", e.target.value)
                        }
                      />
                    </Field>
                  )}
                  {!driver && !milestone && f.discountKind === "percent" && (
                    <Field label="Percentage off">
                      <input
                        type="number"
                        min={1}
                        max={100}
                        className={inputClass}
                        value={f.percent}
                        onChange={(e) => update("percent", e.target.value)}
                      />
                    </Field>
                  )}
                  {!driver &&
                    ((!milestone && f.discountKind === "fixed") ||
                      (milestone && !free)) && (
                      <Field label="Fare credit ($)">
                        <input
                          type="number"
                          min="0.01"
                          step="0.01"
                          className={inputClass}
                          value={milestone ? f.reward : f.discount}
                          onChange={(e) =>
                            update(
                              milestone ? "reward" : "discount",
                              e.target.value,
                            )
                          }
                        />
                      </Field>
                    )}
                  {free && (
                    <>
                      <Field label="Limit free ride by">
                        <select
                          className={inputClass}
                          value={f.limitKind}
                          onChange={(e) => update("limitKind", e.target.value)}
                        >
                          <option value="distance">Distance</option>
                          <option value="amount">Dollar amount</option>
                        </select>
                      </Field>
                      {f.limitKind === "distance" ? (
                        <Field label="Maximum covered distance (miles)">
                          <input
                            type="number"
                            min="0.1"
                            max={200}
                            step="0.1"
                            className={inputClass}
                            value={f.miles}
                            onChange={(e) => update("miles", e.target.value)}
                          />
                        </Field>
                      ) : (
                        <Field label="Maximum covered fare ($)">
                          <input
                            type="number"
                            min="0.01"
                            step="0.01"
                            className={inputClass}
                            value={f.maxDiscount}
                            onChange={(e) =>
                              update("maxDiscount", e.target.value)
                            }
                          />
                        </Field>
                      )}
                      {f.limitKind === "distance" && (
                        <label className="flex items-center gap-2 text-sm sm:col-span-2">
                          <input
                            type="checkbox"
                            checked={f.payExcess}
                            onChange={(e) =>
                              update("payExcess", e.target.checked)
                            }
                          />
                          Rider pays fare above {f.miles} miles{" "}
                          {f.payExcess
                            ? ""
                            : "(over-limit trips will not qualify)"}
                        </label>
                      )}
                    </>
                  )}
                  {!driver && !free && f.discountKind === "percent" && (
                    <Field label="Maximum discount ($, optional)">
                      <input
                        type="number"
                        min="0.01"
                        step="0.01"
                        className={inputClass}
                        value={f.maxDiscount}
                        onChange={(e) => update("maxDiscount", e.target.value)}
                      />
                    </Field>
                  )}
                  {!driver && milestone && (
                    <Field label="Earned reward expires after (days)">
                      <input
                        type="number"
                        min={1}
                        max={365}
                        className={inputClass}
                        value={f.expires}
                        onChange={(e) => update("expires", e.target.value)}
                      />
                    </Field>
                  )}
                  <p className="text-xs leading-5 text-muted sm:col-span-2">
                    {driver
                      ? "Completed, successfully settled regular rides qualify. Bonuses are added to full-fare earnings."
                      : "Fare and booking fee are covered within the limit. For distance rewards, fare is prorated by covered trip distance; excess distance/time and extras remain payable. Discounted reward rides do not advance rider milestones."}
                  </p>
                </div>
              </section>
              <section
                id="promotion-1"
                className="scroll-mt-5 space-y-4 border-t border-line pt-6"
              >
                <Heading n={2} title="How is it applied, and who can use it?" />
                <div className="grid gap-3 sm:grid-cols-2">
                  <Choice
                    selected={f.applicationMode === "automatic"}
                    label="Apply automatically"
                    detail="Rydr tracks eligible rides and applies the best reward."
                    onClick={() => update("applicationMode", "automatic")}
                  />
                  <Choice
                    selected={f.applicationMode === "code"}
                    label="Require a promo code"
                    detail="Validate the code and enroll an eligible account."
                    onClick={() => update("applicationMode", "code")}
                  />
                </div>
                {f.applicationMode === "code" && (
                  <Field label="Unique promo code">
                    <input
                      className={`${inputClass} uppercase`}
                      value={f.promoCode}
                      maxLength={32}
                      onChange={(e) =>
                        update("promoCode", e.target.value.toUpperCase())
                      }
                      placeholder="Write your own code"
                    />
                  </Field>
                )}
                <div className="flex flex-wrap gap-2">
                  {[
                    ["all", "All accounts"],
                    ["new", driver ? "New drivers" : "New riders"],
                    ["beta", "Beta accounts"],
                    ["specific", "Specific accounts"],
                  ].map(([v, label]) => (
                    <Chip
                      key={v}
                      selected={f.audienceRule === v}
                      onClick={() => update("audienceRule", v)}
                    >
                      {label}
                    </Chip>
                  ))}
                </div>
                {f.audienceRule === "specific" && (
                  <Field label="Eligible Firebase account IDs (comma separated)">
                    <textarea
                      className={inputClass}
                      value={f.audienceUserIds}
                      onChange={(e) =>
                        update("audienceUserIds", e.target.value)
                      }
                    />
                  </Field>
                )}
                <div className="grid gap-4 sm:grid-cols-2">
                  <div>
                    <p className="mb-2 text-xs font-semibold text-muted">
                      Markets · none selected means all
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {["Atlanta", "New York", "New Jersey"].map((v) => (
                        <Chip
                          key={v}
                          selected={f.markets.includes(v)}
                          onClick={() => toggle("markets", v)}
                        >
                          {v}
                        </Chip>
                      ))}
                    </div>
                  </div>
                  <div>
                    <p className="mb-2 text-xs font-semibold text-muted">
                      Ride types · none selected means all
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {["Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine"].map(
                        (v) => (
                          <Chip
                            key={v}
                            selected={f.rideTypes.includes(v)}
                            onClick={() => toggle("rideTypes", v)}
                          >
                            {v}
                          </Chip>
                        ),
                      )}
                    </div>
                  </div>
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field
                    label={
                      f.audienceRule === "new"
                        ? "Rewards per new account (blank = 1)"
                        : driver
                          ? "Bonus rewards per driver (blank = unlimited)"
                          : "Rewards per rider (blank = unlimited)"
                    }
                  >
                    <input
                      type="number"
                      min={1}
                      className={inputClass}
                      value={f.perUser}
                      onChange={(e) => update("perUser", e.target.value)}
                    />
                  </Field>
                  <Field label="Total rewards available (blank = unlimited)">
                    <input
                      type="number"
                      min={1}
                      className={inputClass}
                      value={f.total}
                      onChange={(e) => update("total", e.target.value)}
                    />
                  </Field>
                </div>
              </section>
              <section
                id="promotion-2"
                className="scroll-mt-5 space-y-4 border-t border-line pt-6"
              >
                <Heading n={3} title="When is it active?" />
                <div className="grid gap-3 sm:grid-cols-2">
                  <Choice
                    selected={f.startNow}
                    label="Start on publication"
                    onClick={() => update("startNow", true)}
                  />
                  <Choice
                    selected={!f.startNow}
                    label="Schedule a start"
                    onClick={() => update("startNow", false)}
                  />
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  {!f.startNow && (
                    <Field label="Starts · Eastern Time">
                      <input
                        type="datetime-local"
                        className={inputClass}
                        value={f.starts}
                        onChange={(e) => update("starts", e.target.value)}
                      />
                    </Field>
                  )}
                  <Field label="Ends · Eastern Time">
                    <input
                      type="datetime-local"
                      className={inputClass}
                      value={f.ends}
                      onChange={(e) => update("ends", e.target.value)}
                    />
                  </Field>
                </div>
                <p className="text-xs text-muted">
                  Eastern Time adjusts automatically for daylight saving. Earned
                  rider rewards keep their own expiration after the campaign
                  ends.
                </p>
              </section>
            </div>
          )}
          {error && (
            <p
              role="alert"
              className="mt-5 rounded-xl bg-red-50 p-3 text-sm text-red-700"
            >
              {error}
            </p>
          )}
          <div className="mt-6 flex justify-end border-t border-line pt-5">
            <button
              type="button"
              disabled={saving || !ready}
              onClick={() => {
                if (review) void submit(false);
                else {
                  setReview(true);
                  setActiveStep(3);
                }
              }}
              className={`${gradient} rounded-xl px-6 py-3 text-sm font-semibold text-white shadow-md disabled:opacity-40`}
            >
              {saving
                ? "Saving…"
                : review
                  ? "Publish promotion"
                  : "Continue to review →"}
            </button>
          </div>
        </div>
        <aside className="space-y-4 xl:sticky xl:top-5">
          <div className="rounded-3xl border border-line bg-white p-5 shadow-sm">
            <p className="mb-4 text-xs font-bold uppercase tracking-widest text-muted">
              {driver ? "Driver preview" : "Rider preview"}
            </p>
            <div
              className={`${gradient} overflow-hidden rounded-2xl p-6 text-white shadow-md`}
            >
              <p className="mb-8 text-2xl font-bold">Rydr</p>
              <h2 className="text-2xl font-bold leading-tight">
                {f.title || offer}
              </h2>
              <p className="mt-3 text-sm text-white/90">
                {f.description || offer}
              </p>
              {milestone && (
                <div
                  className="mt-6 flex items-center gap-2"
                  aria-label={`${f.milestone} rides to earn reward`}
                >
                  {Array.from(
                    { length: Math.min(Number(f.milestone) || 1, 5) },
                    (_, i) => (
                      <span
                        key={i}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-white/20 text-xs"
                      >
                        {i + 1}
                      </span>
                    ),
                  )}
                  <span className="ml-auto rounded-full bg-white px-3 py-2 text-xs font-bold text-fuchsia-700">
                    {driver ? "BONUS" : "REWARD"}
                  </span>
                </div>
              )}
              {limit && (
                <p className="mt-5 text-right text-sm font-semibold">{limit}</p>
              )}
            </div>
            <dl className="mt-5 space-y-4 text-sm">
              <Summary
                label="Audience"
                value={`${f.audienceRule} ${f.audience}`}
              />
              <Summary
                label="Ride types"
                value={f.rideTypes.join(" + ") || "All eligible types"}
              />
              <Summary
                label="Applied"
                value={
                  f.applicationMode === "code"
                    ? f.promoCode || "Add a code"
                    : "Automatically"
                }
              />
              <Summary label="Normal driver pay" value="Full fare preserved" />
            </dl>
          </div>
          <div className="rounded-2xl border border-emerald-100 bg-emerald-50 p-5">
            <h3 className="font-semibold text-emerald-900">
              {ready ? "Ready for review" : "Finish your promotion"}
            </h3>
            <p className="mt-2 text-sm text-emerald-800">
              {ready
                ? "Review the terms before publishing. Saving a draft does not activate the offer."
                : validationIssue ||
                  "Add a title, eligibility and schedule. Publishing also validates code uniqueness."}
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}
function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="mb-2 block text-xs font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}
function Heading({ n, title }: { n: number; title: string }) {
  return (
    <h2 className="flex items-center gap-3 text-lg font-semibold text-ink">
      <span
        className={`${gradient} flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm text-white`}
      >
        {n}
      </span>
      {title}
    </h2>
  );
}
function Choice({
  selected,
  label,
  detail,
  onClick,
}: {
  selected: boolean;
  label: string;
  detail?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={`rounded-xl border p-3 text-left transition hover:-translate-y-0.5 motion-reduce:transform-none ${selected ? "border-red-400 bg-red-50 shadow-sm" : "border-line hover:border-fuchsia-200"}`}
    >
      <span className="flex items-center justify-between gap-2 text-sm font-semibold">
        {label}
        <span
          className={`h-4 w-4 shrink-0 rounded-full border ${selected ? "border-red-500 bg-red-500 ring-2 ring-red-100" : "border-gray-300"}`}
        />
      </span>
      {detail && (
        <span className="mt-2 block text-xs leading-5 text-muted">
          {detail}
        </span>
      )}
    </button>
  );
}
function Chip({
  selected,
  children,
  onClick,
}: {
  selected: boolean;
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={`rounded-xl border px-3 py-2 text-xs font-medium ${selected ? "border-red-400 bg-red-50 text-red-700" : "border-line bg-white text-muted"}`}
    >
      {children}
    </button>
  );
}
function Summary({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className="text-right font-medium text-ink">{value}</dd>
    </div>
  );
}
