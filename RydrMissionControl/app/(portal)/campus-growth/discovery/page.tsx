import StatusPill from "@/components/StatusPill";
import { DEFAULT_PRIORITY_CATEGORIES, DEFAULT_TARGET_CAMPUSES } from "@/lib/ai/campusGrowthAI";
import { listDiscoveredCampusLeads } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";
import { DiscoveredLeadActions, LeadDiscoveryPanel } from "./LeadDiscoveryClient";

export const dynamic = "force-dynamic";

export default async function LeadDiscoveryPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const leads = filter(await listDiscoveredCampusLeads(500), query, [
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

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">AI Lead Discovery</h1>
        <p className="mt-1 text-sm text-muted">
          Discover public campus leads, then approve or reject before they become usable CRM records.
        </p>
      </div>

      <LeadDiscoveryPanel campuses={DEFAULT_TARGET_CAMPUSES} categories={DEFAULT_PRIORITY_CATEGORIES} />
      <SearchBox placeholder="Search discovered leads, campuses, categories..." />

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        {leads.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No AI-discovered leads yet.</p>
        ) : (
          <div className="divide-y divide-line">
            {leads.map((lead) => (
              <div key={lead.id} className="grid gap-4 px-5 py-4 lg:grid-cols-[1fr_auto]">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium text-ink">{lead.name}</p>
                    <StatusPill status={lead.reviewStatus ?? "pending_review"} />
                    <StatusPill status={lead.kind ?? "organization"} label={lead.kind ?? "organization"} />
                    <StatusPill status="qualified" label={`Score ${lead.relevanceScore ?? 0}`} />
                    <StatusPill status={lead.priorityLevel ?? "medium"} label={`${lead.priorityLevel ?? "medium"} priority`} />
                  </div>
                  <div className="mt-2 grid gap-1 text-xs text-muted md:grid-cols-2">
                    <span>Campus: {lead.campusName || "-"}</span>
                    <span>Category: {lead.category || "-"}</span>
                    <span>Source: {lead.sourceType || "-"}</span>
                    <span>Confidence: {lead.discoveryConfidence ?? 0}/100</span>
                    <span>Reach: {lead.estimatedStudentReach ? lead.estimatedStudentReach.toLocaleString() : "-"}</span>
                    <span>Relationship: {lead.relationshipStrength || "cold"}</span>
                    <span>Discovered: {timeAgo(toDateSafe(lead.createdAt))}</span>
                  </div>
                  {lead.description && <p className="mt-2 text-xs leading-5 text-muted">{lead.description}</p>}
                  {lead.tags?.length ? <p className="mt-2 text-xs text-muted">Tags: {lead.tags.join(", ")}</p> : null}
                  {lead.aiRecommendations?.length ? (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {lead.aiRecommendations.map((recommendation) => (
                        <StatusPill key={recommendation} status="queued" label={recommendation} />
                      ))}
                    </div>
                  ) : null}
                  {lead.sourceUrl && (
                    <a href={lead.sourceUrl} target="_blank" rel="noreferrer" className="mt-2 block truncate text-xs font-medium text-blue-700 hover:underline">
                      {lead.sourceUrl}
                    </a>
                  )}
                  <div className="mt-2 flex flex-wrap gap-3 text-xs">
                    {lead.website && <ExternalLink href={lead.website} label="Website" />}
                    {lead.instagramUrl && <ExternalLink href={lead.instagramUrl} label="Instagram" />}
                    {lead.linkedInUrl && <ExternalLink href={lead.linkedInUrl} label="LinkedIn Org" />}
                    {lead.discordUrl && <ExternalLink href={lead.discordUrl} label="Discord" />}
                    {lead.facebookUrl && <ExternalLink href={lead.facebookUrl} label="Facebook" />}
                  </div>
                  {lead.summary && <p className="mt-2 text-xs leading-5 text-muted">{lead.summary}</p>}
                  {lead.scoreReason && (
                    <p className="mt-2 rounded-md bg-blue-50 px-3 py-2 text-xs leading-5 text-blue-800">Score reason: {lead.scoreReason}</p>
                  )}
                  {lead.outreachAngle && (
                    <p className="mt-2 rounded-md bg-grouped px-3 py-2 text-xs leading-5 text-muted">Outreach angle: {lead.outreachAngle}</p>
                  )}
                  {lead.meetingSchedule && <p className="mt-2 text-xs text-muted">Meeting schedule: {lead.meetingSchedule}</p>}
                  {lead.rejectionReason && <p className="mt-2 rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">{lead.rejectionReason}</p>}
                </div>
                <DiscoveredLeadActions id={lead.id} status={lead.reviewStatus ?? "pending_review"} />
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function ExternalLink({ href, label }: { href: string; label: string }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="font-medium text-blue-700 hover:underline">
      {label}
    </a>
  );
}

function SearchBox({ placeholder }: { placeholder: string }) {
  return (
    <form className="flex gap-2">
      <input name="q" placeholder={placeholder} className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink" />
      <button className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white">Search</button>
    </form>
  );
}

function filter<T extends object>(items: T[], query: string, keys: Array<keyof T>): T[] {
  if (!query) return items;
  return items.filter((item) => keys.some((key) => String(item[key] ?? "").toLowerCase().includes(query)));
}
