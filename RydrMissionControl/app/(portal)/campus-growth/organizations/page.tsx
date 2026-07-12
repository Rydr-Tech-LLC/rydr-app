import StatusPill from "@/components/StatusPill";
import { listCampuses, listOrganizations } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";
import { OrganizationForm } from "../CampusGrowthForms";

export const dynamic = "force-dynamic";

export default async function CampusOrganizationsPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const [campuses, organizationsRaw] = await Promise.all([listCampuses(250), listOrganizations(500)]);
  const organizations = filter(organizationsRaw, query, ["name", "campusName", "category", "publicEmail", "leaderName", "notes"]);

  return (
    <div className="space-y-6">
      <Header title="Student Organization Leads" body="Public orgs and contacts to qualify before outreach." />
      <OrganizationForm campuses={campuses} />
      <SearchBox placeholder="Search organizations, campuses, categories..." />
      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        {organizations.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No organization leads found.</p>
        ) : (
          <div className="divide-y divide-line">
            {organizations.map((org) => (
              <div key={org.id} className="px-5 py-4">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium text-ink">{org.name}</p>
                  <StatusPill status={org.status ?? "new"} />
                  <StatusPill status="qualified" label={`Score ${org.relevanceScore ?? 0}`} />
                </div>
                  <p className="mt-1 text-xs text-muted">
                    {org.campusName || "Unassigned campus"} · {org.category || "No category"} · {org.publicEmail || "No public email"} ·{" "}
                    {timeAgo(toDateSafe(org.createdAt))}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {org.priorityLevel && <StatusPill status={org.priorityLevel} label={`${org.priorityLevel} priority`} />}
                    {org.relationshipStrength && <StatusPill status="queued" label={org.relationshipStrength} />}
                    {org.discoveryConfidence ? <StatusPill status="qualified" label={`Confidence ${org.discoveryConfidence}`} /> : null}
                    {org.lastAIRecommendation && <StatusPill status="queued" label={org.lastAIRecommendation} />}
                  </div>
                  {(org.leaderName || org.leaderTitle) && (
                    <p className="mt-1 text-xs text-muted">
                      Public contact: {[org.leaderName, org.leaderTitle].filter(Boolean).join(", ")}
                    </p>
                  )}
                  {org.tags?.length ? <p className="mt-2 text-xs text-muted">Tags: {org.tags.join(", ")}</p> : null}
                  {org.aiSummary && <p className="mt-2 text-xs leading-5 text-muted">{org.aiSummary}</p>}
                  {org.scoreReason && <p className="mt-2 rounded-md bg-blue-50 px-3 py-2 text-xs text-blue-800">{org.scoreReason}</p>}
                  {org.notes && <p className="mt-2 text-xs leading-5 text-muted">{org.notes}</p>}
                </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Header({ title, body }: { title: string; body: string }) {
  return (
    <div>
      <h1 className="text-xl font-semibold text-ink">{title}</h1>
      <p className="mt-1 text-sm text-muted">{body}</p>
    </div>
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
