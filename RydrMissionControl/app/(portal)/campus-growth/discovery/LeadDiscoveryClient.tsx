"use client";

import type React from "react";
import { useRouter } from "next/navigation";
import { useState } from "react";

export function LeadDiscoveryPanel({ campuses, categories }: { campuses: string[]; categories: string[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [goal, setGoal] = useState("Find campus organizations that can help recruit commuter riders, student ambassadors, interns, or beta testers.");

  async function runDiscovery(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    setBusy(true);
    setMessage(null);
    try {
      const payload = {
        discoveryGoal: String(formData.get("discoveryGoal") ?? ""),
        campusNames: formData.getAll("campusNames"),
        categories: formData.getAll("categories"),
        manualUrls: String(formData.get("manualUrls") ?? "")
          .split(/\n/)
          .map((url) => url.trim())
          .filter(Boolean),
        maxSearchResults: Number(formData.get("maxSearchResults") ?? 5)
      };

      const response = await fetch("/api/campus-growth/ai/discover", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to run lead discovery.");

      setMessage(
        `Discovery complete. Planned ${body.searchStrategyCount ?? 0} searches and saved ${body.savedCount ?? 0} pending leads from ${
          body.searchResultCount ?? 0
        } public results. Blocked ${
          body.rejectedSources?.length ?? 0
        } sources.`
      );
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to run lead discovery.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={runDiscovery} className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-sm font-semibold text-ink">Campus Agent Search</h2>
          <p className="mt-1 text-xs leading-5 text-muted">
            AI plans search queries, checks public results, scores matches, and sends them to review.
          </p>
        </div>
        <button type="submit" disabled={busy} className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">
          {busy ? "Searching..." : "Run AI Search"}
        </button>
      </div>

      <div className="mt-5 rounded-md border border-line bg-grouped p-4">
        <label className="space-y-1 text-xs font-semibold text-muted">
          1. Search goal
          <textarea
            name="discoveryGoal"
            value={goal}
            onChange={(event) => setGoal(event.target.value)}
            rows={3}
            className="mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
          />
        </label>
        <div className="mt-3 flex flex-wrap gap-2">
          <PresetButton label="Commuter riders" onClick={() => setGoal("Find commuter student groups, transportation departments, and student government leads that can help recruit riders for CashRydr beta outreach.")} />
          <PresetButton label="Interns" onClick={() => setGoal("Find computer science, software, ACM, IEEE, startup, and innovation leads that may be useful for Rydr intern recruiting.")} />
          <PresetButton label="Ambassadors" onClick={() => setGoal("Find student organizations and campus leaders likely to help recruit campus ambassadors, beta testers, riders, and drivers.")} />
          <PresetButton label="Events" onClick={() => setGoal("Find public campus events, hackathons, career fairs, student activities, and entrepreneurship events that Rydr could attend or sponsor.")} />
        </div>
      </div>

      <div className="mt-5 grid gap-5 lg:grid-cols-[1fr_1fr]">
        <fieldset className="rounded-md border border-line p-4">
          <legend className="text-xs font-semibold text-muted">2. Target campuses</legend>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {campuses.map((campus) => (
              <label key={campus} className="flex items-center gap-2 text-sm text-ink">
                <input type="checkbox" name="campusNames" value={campus} defaultChecked className="h-4 w-4 rounded border-line" />
                {campus}
              </label>
            ))}
          </div>
        </fieldset>

        <fieldset className="rounded-md border border-line p-4">
          <legend className="text-xs font-semibold text-muted">3. Priority categories</legend>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {categories.map((category) => (
              <label key={category} className="flex items-center gap-2 text-sm text-ink">
                <input type="checkbox" name="categories" value={category} defaultChecked className="h-4 w-4 rounded border-line" />
                {category}
              </label>
            ))}
          </div>
        </fieldset>
      </div>

      <div className="mt-5 grid gap-3 lg:grid-cols-[1fr_180px]">
        <label className="space-y-1 text-xs font-medium text-muted">
          Optional approved URLs
          <textarea
            name="manualUrls"
            rows={4}
            placeholder="One public URL per line"
            className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
          />
        </label>
        <label className="space-y-1 text-xs font-medium text-muted">
          Results per search
          <input
            name="maxSearchResults"
            type="number"
            min={1}
            max={10}
            defaultValue={5}
            className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
          />
        </label>
      </div>

      <div className="mt-4 flex flex-col gap-3 rounded-md border border-line bg-grouped px-3 py-3 md:flex-row md:items-center md:justify-between">
        <p className="text-xs leading-5 text-muted">
        Public-source guardrails: official campus org directories, campus calendars, public department pages, Ticketmaster/public event APIs, and manual URLs are allowed.
        Personal profiles, guessed emails, private directories, and login-required pages are blocked.
        </p>
        <button type="submit" disabled={busy} className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">
          {busy ? "Searching..." : "Run AI Search"}
        </button>
      </div>

      {message && <p className="mt-3 text-xs text-muted">{message}</p>}
    </form>
  );
}

function PresetButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink hover:border-ink"
    >
      {label}
    </button>
  );
}

export function DiscoveredLeadActions({ id, status }: { id: string; status: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function run(action: "approve" | "reject" | "reset") {
    const reason = action === "reject" ? window.prompt("Why is this AI-discovered lead being rejected?") : undefined;
    if (action === "reject" && !reason?.trim()) return;

    setBusy(action);
    setMessage(null);
    try {
      const response = await fetch(`/api/campus-growth/discovered-leads/${id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, reason })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to update lead.");
      setMessage(action === "approve" ? "Approved and converted." : "Updated.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to update lead.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col items-end gap-1.5">
      <div className="flex flex-wrap justify-end gap-1.5">
        <Button label="Approve" disabled={status === "approved"} busy={busy === "approve"} onClick={() => run("approve")} />
        <Button label="Reject" disabled={status === "rejected"} busy={busy === "reject"} danger onClick={() => run("reject")} />
        <Button label="Reset" disabled={status === "pending_review"} busy={busy === "reset"} muted onClick={() => run("reset")} />
      </div>
      {message && <p className="max-w-xs text-right text-[11px] text-muted">{message}</p>}
    </div>
  );
}

function Button({
  label,
  busy,
  disabled,
  muted,
  danger,
  onClick
}: {
  label: string;
  busy: boolean;
  disabled: boolean;
  muted?: boolean;
  danger?: boolean;
  onClick: () => void;
}) {
  const className = danger
    ? "rounded-md bg-red-600 px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40"
    : muted
      ? "rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink disabled:cursor-not-allowed disabled:opacity-40"
      : "rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40";

  return (
    <button type="button" disabled={busy || disabled} onClick={onClick} className={className}>
      {busy ? "Working..." : label}
    </button>
  );
}
