import Link from "next/link";
import StatusPill from "@/components/StatusPill";
import { DEFAULT_PRIORITY_CATEGORIES, DEFAULT_TARGET_CAMPUSES } from "@/lib/ai/campusGrowthAI";
import { listDiscoveredCampusLeads, type DiscoveredCampusLead } from "@/lib/campusGrowth";
import { DiscoveredLeadActions, LeadDiscoveryPanel } from "./LeadDiscoveryClient";

export const dynamic = "force-dynamic";

export default async function LeadDiscoveryPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const allLeads = await listDiscoveredCampusLeads(500);
  const leads = filter(allLeads, query, [
    "name",
    "campusName",
    "category",
    "sourceType",
    "summary",
    "outreachAngle",
    "scoreReason",
    "lastAIRecommendation",
    "reviewStatus"
  ]);
  const pendingCount = allLeads.filter((lead) => (lead.reviewStatus ?? "pending_review") === "pending_review").length;

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted">
            <Link href="/campus-growth" className="font-semibold text-ink hover:underline">
              Campus Growth
            </Link>
            <span>/</span>
            <span>AI Discovery</span>
          </div>
          <h1 className="mt-3 text-2xl font-semibold text-ink">Find Campus Leads</h1>
          <p className="mt-1 text-sm text-muted">
            Describe who you need, choose trusted sources, then review every match before it enters the CRM.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusPill status="active" label="Agent Ready" />
          <Link href="#discovered-leads" className="rounded-md border border-line bg-white px-4 py-2 text-xs font-semibold text-ink shadow-sm">
            View Pending Leads <span className="ml-2 rounded-full bg-grouped px-2 py-0.5">{pendingCount}</span>
          </Link>
          <Link href="/campus-growth" className="rounded-md border border-line bg-white px-4 py-2 text-xs font-semibold text-ink shadow-sm">
            Back to Dashboard
          </Link>
        </div>
      </div>

      <LeadDiscoveryPanel campuses={DEFAULT_TARGET_CAMPUSES} categories={DEFAULT_PRIORITY_CATEGORIES} pendingCount={pendingCount} />

      <div id="discovered-leads" className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <div className="flex flex-col gap-3 border-b border-line px-5 py-4 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-base font-semibold text-ink">Discovered Leads</h2>
            <StatusPill status="pending_review" label="Pending Review" />
          </div>
          <div className="flex flex-wrap gap-2">
            <SearchBox placeholder="Search leads..." />
            <span className="rounded-md bg-grouped px-3 py-2 text-xs font-semibold text-muted">{leads.length} leads</span>
          </div>
        </div>

        {leads.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No AI-discovered leads yet. Run an AI search to populate this queue.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[920px] text-left text-xs">
              <thead className="border-b border-line bg-grouped text-muted">
                <tr>
                  <th className="px-5 py-3 font-semibold">Lead</th>
                  <th className="px-5 py-3 font-semibold">Match</th>
                  <th className="px-5 py-3 font-semibold">Source</th>
                  <th className="px-5 py-3 font-semibold">Status</th>
                  <th className="px-5 py-3 font-semibold">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {leads.map((lead) => (
                  <tr key={lead.id} className="align-top">
                    <td className="px-5 py-4">
                      <div className="flex items-start gap-3">
                        <LeadAvatar lead={lead} />
                        <div className="min-w-0">
                          <p className="font-semibold text-ink">{lead.name || "Unnamed lead"}</p>
                          <p className="mt-1 text-muted">{lead.campusName || "Unassigned campus"}</p>
                          {lead.category && <p className="mt-2 w-fit rounded-md border border-line bg-grouped px-2 py-1 text-[11px] text-ink">{lead.category}</p>}
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-4">
                      <p className="text-lg font-semibold text-emerald-700">{lead.relevanceScore ?? 0}%</p>
                      <div className="mt-2 h-1.5 w-28 rounded-full bg-grouped">
                        <div className="h-1.5 rounded-full bg-emerald-600" style={{ width: `${Math.min(Math.max(lead.relevanceScore ?? 0, 0), 100)}%` }} />
                      </div>
                      <p className="mt-2 text-muted">Confidence {lead.discoveryConfidence ?? 0}/100</p>
                    </td>
                    <td className="px-5 py-4">
                      {lead.sourceUrl ? (
                        <a href={lead.sourceUrl} target="_blank" rel="noreferrer" className="block max-w-xs truncate font-medium text-blue-700 hover:underline">
                          {trimSource(lead.sourceUrl)}
                        </a>
                      ) : (
                        <span className="text-muted">No source</span>
                      )}
                      <p className="mt-1 text-muted">{lead.sourceType || "Public source"}</p>
                    </td>
                    <td className="px-5 py-4">
                      <StatusPill status={lead.reviewStatus ?? "pending_review"} />
                    </td>
                    <td className="px-5 py-4">
                      <DiscoveredLeadActions id={lead.id} status={lead.reviewStatus ?? "pending_review"} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="border-t border-line px-5 py-3 text-xs text-muted">All leads require human approval before being added to the CRM.</p>
          </div>
        )}
      </div>
    </div>
  );
}

function LeadAvatar({ lead }: { lead: DiscoveredCampusLead }) {
  const label = (lead.name || lead.campusName || "L")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
  return <span className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-rydr-red text-xs font-bold text-white">{label || "L"}</span>;
}

function SearchBox({ placeholder }: { placeholder: string }) {
  return (
    <form className="flex w-full gap-2 sm:w-auto">
      <input name="q" placeholder={placeholder} className="min-w-0 flex-1 rounded-md border border-line bg-white px-3 py-2 text-xs text-ink outline-none focus:border-rydr-red sm:w-64 sm:flex-none" />
      <button className="rounded-md border border-line bg-white px-3 py-2 text-xs font-semibold text-ink">Search</button>
    </form>
  );
}

function trimSource(value: string) {
  try {
    const url = new URL(value);
    return `${url.hostname}${url.pathname}`.replace(/\/$/, "");
  } catch {
    return value;
  }
}

function filter<T extends object>(items: T[], query: string, keys: Array<keyof T>): T[] {
  if (!query) return items;
  return items.filter((item) => keys.some((key) => String(item[key] ?? "").toLowerCase().includes(query)));
}
