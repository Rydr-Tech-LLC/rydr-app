"use client";

import type React from "react";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

const LEAD_INTENTS = [
  { label: "Commuter riders", value: "commuter riders" },
  { label: "Interns", value: "intern recruiting" },
  { label: "Ambassadors", value: "campus ambassadors" },
  { label: "Student leaders", value: "public campus student leaders" },
  { label: "Social accounts", value: "public campus-affiliated social accounts" },
  { label: "Events", value: "campus events" }
];

interface DiscoveryRunResponse {
  savedCount?: number;
  searchResultCount?: number;
  searchStrategyCount?: number;
  searchStrategies?: string[];
  searchProviderConfigured?: boolean;
  searchErrors?: Array<{ query?: string; status?: number; error?: string }>;
  warnings?: string[];
  rejectedSources?: Array<{ url?: string; reason?: string }>;
}

interface SearchHealthResponse {
  ok?: boolean;
  configured?: boolean;
  provider?: string;
  hasApiKey?: boolean;
  status?: number;
  braveErrorCode?: string;
  error?: string;
  resultCount?: number;
  requestCap?: number;
  manualUrlProvider?: string;
  manualUrlConfigured?: boolean;
  warning?: string | null;
}

export function LeadDiscoveryPanel({ campuses, categories, pendingCount }: { campuses: string[]; categories: string[]; pendingCount: number }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [healthBusy, setHealthBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [lastRun, setLastRun] = useState<DiscoveryRunResponse | null>(null);
  const [searchHealth, setSearchHealth] = useState<SearchHealthResponse | null>(null);
  const [goal, setGoal] = useState("Find public campus organizations, student leaders, ambassadors, and social accounts that can be contacted about commuter riders, internships, and beta testing.");
  const [selectedIntents, setSelectedIntents] = useState<string[]>(LEAD_INTENTS.map((intent) => intent.value));
  const [selectedCampuses, setSelectedCampuses] = useState<string[]>(campuses);
  const [selectedCategories, setSelectedCategories] = useState<string[]>(categories);
  const [campusSearch, setCampusSearch] = useState("");
  const [categorySearch, setCategorySearch] = useState("");
  const [manualUrls, setManualUrls] = useState("");
  const [maxSearchResults, setMaxSearchResults] = useState(5);

  const filteredCampuses = useMemo(
    () => campuses.filter((campus) => campus.toLowerCase().includes(campusSearch.toLowerCase())).slice(0, 8),
    [campuses, campusSearch]
  );
  const filteredCategories = useMemo(
    () => categories.filter((category) => category.toLowerCase().includes(categorySearch.toLowerCase())).slice(0, 8),
    [categories, categorySearch]
  );
  const manualUrlCount = manualUrls.split(/\n/).map((url) => url.trim()).filter(Boolean).length;

  async function runDiscovery(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    setLastRun(null);
    try {
      const payload = {
        discoveryGoal: goal,
        leadIntents: selectedIntents,
        campusNames: selectedCampuses,
        categories: selectedCategories,
        manualUrls: manualUrls
          .split(/\n/)
          .map((url) => url.trim())
          .filter(Boolean),
        maxSearchResults
      };

      const response = await fetch("/api/campus-growth/ai/discover", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(body.error ?? `Unable to run lead discovery. HTTP ${response.status}`);
      }
      setLastRun(body);

      const resultCount = body.searchResultCount ?? 0;
      const savedCount = body.savedCount ?? 0;
      if (resultCount === 0) {
        setMessage("No public search results came back, so the AI had no source pages to turn into leads.");
      } else if (savedCount === 0) {
        setMessage("Public pages were found, but no usable leads were extracted. Try a broader goal or add approved URLs.");
      } else {
        setMessage(`Search complete. Saved ${savedCount} pending leads from ${resultCount} public results.`);
      }
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to run lead discovery.");
    } finally {
      setBusy(false);
    }
  }

  async function testSearchConnection() {
    setHealthBusy(true);
    setSearchHealth(null);
    try {
      const response = await fetch("/api/campus-growth/ai/search-health", { method: "GET" });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to test Brave Search.");
      setSearchHealth(body);
    } catch (error) {
      setSearchHealth({
        ok: false,
        configured: false,
        provider: "brave_web",
        error: error instanceof Error ? error.message : "Unable to test Brave Search."
      });
    } finally {
      setHealthBusy(false);
    }
  }

  return (
    <form onSubmit={runDiscovery} className="grid gap-4 xl:grid-cols-[1.55fr_1fr]">
      <div className="space-y-4">
        <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
          <div className="grid grid-cols-3 gap-2">
            <StepPill number="1" title="Describe" body="Goal and intent" active />
            <StepPill number="2" title="Target" body="Campuses and categories" active />
            <StepPill number="3" title="Review" body="Run and preview results" />
          </div>
        </div>

        <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
          <div className="flex items-center justify-between gap-3">
            <label className="text-sm font-semibold text-ink" htmlFor="discoveryGoal">
              What should the agent find?
            </label>
            <span className="text-xs text-muted">{goal.length} / 500 characters</span>
          </div>
          <textarea
            id="discoveryGoal"
            value={goal}
            onChange={(event) => setGoal(event.target.value.slice(0, 500))}
            rows={4}
            className="mt-3 w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-rydr-red"
          />

          <div className="mt-4 flex items-center justify-between gap-3">
            <p className="text-xs font-semibold text-muted">Lead intents</p>
            <p className="text-xs text-muted">{selectedIntents.length} selected</p>
          </div>
          <div className="mt-2 flex flex-wrap gap-2">
            {LEAD_INTENTS.map((intent) => (
              <ToggleChip
                key={intent.value}
                label={intent.label}
                selected={selectedIntents.includes(intent.value)}
                onClick={() => toggleValue(intent.value, selectedIntents, setSelectedIntents)}
              />
            ))}
          </div>
        </div>

        <div className="grid gap-4 lg:grid-cols-2">
          <SelectorCard
            title="Target campuses"
            helper="Choose the campuses to search."
            searchValue={campusSearch}
            searchPlaceholder="Search campuses..."
            onSearch={setCampusSearch}
            selected={selectedCampuses}
            visibleOptions={filteredCampuses}
            allOptions={campuses}
            onChange={setSelectedCampuses}
          />
          <SelectorCard
            title="Priority categories"
            helper="Focus on the most relevant categories."
            searchValue={categorySearch}
            searchPlaceholder="Search categories..."
            onSearch={setCategorySearch}
            selected={selectedCategories}
            visibleOptions={filteredCategories}
            allOptions={categories}
            onChange={setSelectedCategories}
          />
        </div>

        <div className="rounded-lg border border-line bg-white shadow-sm">
          <details>
            <summary className="flex cursor-pointer items-center justify-between gap-3 px-5 py-4 text-sm font-semibold text-ink">
              Approved public URLs
              <span className="rounded-md bg-grouped px-2 py-1 text-xs text-muted">{manualUrlCount} URLs added</span>
            </summary>
            <div className="border-t border-line px-5 py-4">
              <textarea
                value={manualUrls}
                onChange={(event) => setManualUrls(event.target.value)}
                rows={4}
                placeholder="One approved public URL per line"
                className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-rydr-red"
              />
            </div>
          </details>
        </div>

        <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
          <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-sm font-semibold text-ink">Results per search</p>
              <p className="mt-1 text-xs text-muted">Choose how many results the agent should inspect per planned search.</p>
            </div>
            <div className="inline-flex w-fit overflow-hidden rounded-md border border-line">
              {[5, 10, 20].map((value) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setMaxSearchResults(value)}
                  className={`px-5 py-2 text-xs font-semibold ${
                    maxSearchResults === value ? "bg-red-50 text-rydr-red ring-1 ring-inset ring-rydr-red" : "bg-white text-muted hover:text-ink"
                  }`}
                >
                  {value}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      <aside className="space-y-4">
        <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
          <h2 className="text-base font-semibold text-ink">Search Summary</h2>
          <div className="mt-5 grid grid-cols-2 gap-3">
            <SummaryTile label="Campuses" value={selectedCampuses.length} />
            <SummaryTile label="Categories" value={selectedCategories.length} />
            <SummaryTile label="Lead intents" value={selectedIntents.length} />
            <SummaryTile label="Results" value={maxSearchResults} helper="per search" />
          </div>

          <div className="mt-5 space-y-2">
            <p className="text-xs font-semibold text-muted">Sources the agent can use</p>
            {["Campus organization directories", "Campus event calendars", "Public department pages", "Ticketmaster / public event APIs", "Approved URLs"].map((source) => (
              <div key={source} className="flex items-center gap-2 text-xs text-muted">
                <span className="flex h-4 w-4 items-center justify-center rounded-full bg-emerald-600 text-[10px] font-semibold text-white">✓</span>
                {source}
              </div>
            ))}
          </div>

          <div className="mt-5 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-3">
            <p className="text-sm font-semibold text-ink">Public sources only</p>
            <p className="mt-1 text-xs leading-5 text-muted">Personal profiles, guessed emails, private directories, and login-required pages are blocked.</p>
          </div>

          <button
            type="submit"
            disabled={busy || selectedCampuses.length === 0 || selectedCategories.length === 0 || !goal.trim()}
            className="mt-5 w-full rounded-md bg-gradient-to-r from-rydr-red to-rydr-burgundy px-4 py-3 text-sm font-semibold text-white shadow-sm disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? "Running AI Search..." : "Run AI Search"}
          </button>
          <button
            type="button"
            onClick={testSearchConnection}
            disabled={healthBusy}
            className="mt-3 w-full rounded-md border border-line bg-white px-4 py-2.5 text-sm font-semibold text-ink shadow-sm hover:border-rydr-red hover:text-rydr-red disabled:cursor-not-allowed disabled:opacity-50"
          >
            {healthBusy ? "Testing Brave..." : "Test Brave Search"}
          </button>
          <p className="mt-3 text-center text-xs text-muted">
            Every result enters Pending Review. Nothing is contacted automatically.
          </p>
          {searchHealth ? (
            <div
              className={`mt-4 rounded-md border px-3 py-3 text-xs leading-5 ${
                searchHealth.ok ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-amber-200 bg-amber-50 text-amber-900"
              }`}
            >
              <p className="font-semibold">{searchHealth.ok ? "Brave Search connected" : "Brave Search needs attention"}</p>
              {searchHealth.ok ? (
                <p className="mt-1">
                  Test returned {searchHealth.resultCount ?? 0} result preview. Per-run AI search cap is {searchHealth.requestCap ?? 100} Brave requests.
                  {searchHealth.warning ? ` ${searchHealth.warning}` : ""}
                  {searchHealth.manualUrlConfigured === false ? " Firecrawl is not configured for approved URL extraction." : ""}
                </p>
              ) : (
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {searchHealth.configured === false && <li>Mission Control is missing the Brave Search API key env var.</li>}
                  {searchHealth.status && <li>Brave HTTP status: {searchHealth.status}</li>}
                  {searchHealth.braveErrorCode && <li>Brave error code: {searchHealth.braveErrorCode}</li>}
                  {searchHealth.error && <li>{searchHealth.error}</li>}
                  <li>Env check: Brave Search API key {searchHealth.hasApiKey ? "present" : "missing"}.</li>
                  <li>Per-run AI search cap: {searchHealth.requestCap ?? 100} Brave requests.</li>
                </ul>
              )}
            </div>
          ) : null}
          {message && <p className="mt-4 rounded-md bg-grouped px-3 py-2 text-xs leading-5 text-muted">{message}</p>}
          {lastRun?.searchStrategies?.length ? (
            <details className="mt-3 rounded-md border border-line bg-white px-3 py-3 text-xs text-muted">
              <summary className="cursor-pointer font-semibold text-ink">
                Planned searches ({lastRun.searchStrategies.length})
              </summary>
              <ol className="mt-2 list-decimal space-y-1 pl-4">
                {lastRun.searchStrategies.map((strategy) => (
                  <li key={strategy} className="break-words">{strategy}</li>
                ))}
              </ol>
            </details>
          ) : null}
          {lastRun && (lastRun.warnings?.length || lastRun.searchErrors?.length || (lastRun.searchResultCount ?? 0) === 0) ? (
            <div className="mt-3 rounded-md border border-amber-200 bg-amber-50 px-3 py-3 text-xs leading-5 text-amber-900">
              <p className="font-semibold">Search diagnostics</p>
              <ul className="mt-2 list-disc space-y-1 pl-4">
                {(lastRun.warnings ?? []).map((warning) => (
                  <li key={warning}>{warning}</li>
                ))}
                {lastRun.searchProviderConfigured === false && <li>Brave Search is not connected, so only approved URLs can produce leads.</li>}
                {(lastRun.searchErrors ?? []).slice(0, 3).map((error, index) => (
                  <li key={`${error.query ?? "query"}-${index}`}>
                    {error.status ? `Brave status ${error.status}: ` : ""}
                    {error.error ?? "Search provider error."}
                  </li>
                ))}
              </ul>
              <p className="mt-2">
                Next step: verify the Brave Search env var, quota, and billing, or paste one official campus organization/event URL into Approved public URLs and run again.
              </p>
            </div>
          ) : null}
        </div>

        <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-ink">Pending leads</p>
              <p className="mt-1 text-xs text-muted">Review queue after AI search.</p>
            </div>
            <span className="rounded-full bg-grouped px-3 py-1 text-sm font-semibold text-ink">{pendingCount}</span>
          </div>
        </div>
      </aside>
    </form>
  );
}

function StepPill({ number, title, body, active }: { number: string; title: string; body: string; active?: boolean }) {
  return (
    <div className="flex items-center gap-3 rounded-md border border-line px-3 py-3">
      <span className={`flex h-9 w-9 items-center justify-center rounded-full border text-sm font-semibold ${active ? "border-rydr-red text-rydr-red" : "border-muted/40 text-muted"}`}>
        {number}
      </span>
      <span>
        <span className="block text-xs font-semibold text-ink">{title}</span>
        <span className="block text-[11px] text-muted">{body}</span>
      </span>
    </div>
  );
}

function ToggleChip({ label, selected, onClick }: { label: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-md border px-3 py-2 text-xs font-semibold ${
        selected ? "border-red-200 bg-red-50 text-rydr-red" : "border-line bg-white text-muted hover:text-ink"
      }`}
    >
      {selected ? "✓ " : ""}
      {label}
    </button>
  );
}

function SelectorCard({
  title,
  helper,
  searchValue,
  searchPlaceholder,
  onSearch,
  selected,
  visibleOptions,
  allOptions,
  onChange
}: {
  title: string;
  helper: string;
  searchValue: string;
  searchPlaceholder: string;
  onSearch: (value: string) => void;
  selected: string[];
  visibleOptions: string[];
  allOptions: string[];
  onChange: (value: string[]) => void;
}) {
  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-ink">{title}</h2>
          <p className="mt-1 text-xs text-muted">{helper}</p>
        </div>
        <span className="text-xs text-muted">{selected.length} selected</span>
      </div>
      <input
        value={searchValue}
        onChange={(event) => onSearch(event.target.value)}
        placeholder={searchPlaceholder}
        className="mt-3 w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-rydr-red"
      />
      <div className="mt-3 flex flex-wrap gap-2">
        {visibleOptions.map((option) => (
          <Chip key={option} label={option} selected={selected.includes(option)} onClick={() => toggleValue(option, selected, onChange)} />
        ))}
      </div>
      <div className="mt-3 flex items-center justify-between text-xs">
        <button type="button" onClick={() => onChange([])} className="font-semibold text-muted hover:text-ink">
          Clear all
        </button>
        <button type="button" onClick={() => onChange(allOptions)} className="font-semibold text-muted hover:text-ink">
          Select all
        </button>
      </div>
    </div>
  );
}

function Chip({ label, selected, onClick }: { label: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`max-w-full truncate rounded-md border px-3 py-1.5 text-xs ${
        selected ? "border-line bg-grouped text-ink" : "border-line bg-white text-muted opacity-70"
      }`}
    >
      {label}
      {selected ? " ×" : ""}
    </button>
  );
}

function SummaryTile({ label, value, helper }: { label: string; value: number; helper?: string }) {
  return (
    <div className="rounded-md border border-line bg-white p-3 text-center">
      <p className="text-2xl font-semibold text-ink">{value}</p>
      <p className="mt-1 text-xs text-muted">{helper ?? label}</p>
    </div>
  );
}

function toggleValue(value: string, selected: string[], onChange: (value: string[]) => void) {
  onChange(selected.includes(value) ? selected.filter((item) => item !== value) : [...selected, value]);
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
        <Button label="Approve Lead" disabled={status === "approved"} busy={busy === "approve"} onClick={() => run("approve")} />
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
      : "rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink disabled:cursor-not-allowed disabled:opacity-40";

  return (
    <button type="button" disabled={busy || disabled} onClick={onClick} className={className}>
      {busy ? "Working..." : label}
    </button>
  );
}
