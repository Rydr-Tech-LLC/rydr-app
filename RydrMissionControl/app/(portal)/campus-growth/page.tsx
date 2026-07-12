import Link from "next/link";
import StatusPill from "@/components/StatusPill";
import { campusGrowthAnalytics, campusGrowthCounts, listOutreachDrafts } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";

export const dynamic = "force-dynamic";

const SECTIONS = [
  { href: "/campus-growth/discovery", title: "AI Discovery", body: "Find public campus leads and route them into pending review." },
  { href: "/campus-growth/campuses", title: "Campuses", body: "Target markets, owners, priorities, and research notes." },
  { href: "/campus-growth/organizations", title: "Organizations", body: "Public student org leads scored by relevance." },
  { href: "/campus-growth/events", title: "Events", body: "Campus and public events that may support outreach." },
  { href: "/campus-growth/outreach", title: "Outreach Inbox", body: "Drafts waiting for approval, denial, or sent/reply tracking." },
  { href: "/campus-growth/ambassadors", title: "Ambassadors", body: "Prospects who can help recruit interns, riders, and drivers." }
];

export default async function CampusGrowthPage() {
  const [counts, analytics, drafts] = await Promise.all([campusGrowthCounts(), campusGrowthAnalytics(), listOutreachDrafts(8)]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Campus Growth</h1>
        <p className="mt-1 text-sm text-muted">
          Public lead tracking, relevance scoring, outreach approval, and ambassador recruiting.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-6">
        <Tile label="Campuses" value={counts.campuses} />
        <Tile label="Organizations" value={counts.organizations} />
        <Tile label="Events" value={counts.events} />
        <Tile label="AI Pending" value={counts.pendingDiscoveredLeads} />
        <Tile label="AI Approved" value={counts.approvedDiscoveredLeads} />
        <Tile label="Drafts Pending" value={counts.pendingDrafts} />
        <Tile label="Ambassadors" value={counts.ambassadors} />
      </div>

      <div className="grid gap-3 lg:grid-cols-3">
        <AnalyticsCard title="Lead Conversion Funnel" rows={analytics.funnel} />
        <AnalyticsCard title="Top Schools" rows={analytics.topSchools} emptyLabel="No schools yet" />
        <AnalyticsCard title="Top Categories" rows={analytics.topCategories} emptyLabel="No categories yet" />
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Tile label="Organizations Discovered" value={analytics.organizationsDiscovered} />
        <Tile label="Events Discovered" value={analytics.eventsDiscovered} />
        <Tile label="Intern Prospects" value={analytics.internProspects} />
        <Tile label="Ambassador Prospects" value={analytics.ambassadorProspects} />
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {SECTIONS.map((section) => (
          <Link key={section.href} href={section.href} className="rounded-lg border border-line bg-white p-4 shadow-sm hover:border-ink">
            <h2 className="text-sm font-semibold text-ink">{section.title}</h2>
            <p className="mt-2 text-xs leading-5 text-muted">{section.body}</p>
          </Link>
        ))}
      </div>

      <div className="rounded-lg border border-line bg-white shadow-sm">
        <div className="border-b border-line px-5 py-3">
          <h2 className="text-sm font-semibold text-ink">Recent Outreach Drafts</h2>
        </div>
        {drafts.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No outreach drafts yet.</p>
        ) : (
          <div className="divide-y divide-line">
            {drafts.map((draft) => (
              <div key={draft.id} className="px-5 py-4">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium text-ink">{draft.subject ?? "Untitled draft"}</p>
                  <StatusPill status={draft.status ?? "draft"} />
                </div>
                <p className="mt-1 text-xs text-muted">
                  To {draft.recipientEmail || draft.recipientName || "unassigned"} from {draft.fromEmail ?? "support@rydr-go.com"} ·{" "}
                  {timeAgo(toDateSafe(draft.createdAt))}
                </p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Tile({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className="mt-1.5 text-2xl font-semibold text-ink">{value}</p>
    </div>
  );
}

function AnalyticsCard({
  title,
  rows,
  emptyLabel = "No data yet"
}: {
  title: string;
  rows: Array<{ label: string; value: number }>;
  emptyLabel?: string;
}) {
  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <h2 className="text-sm font-semibold text-ink">{title}</h2>
      {rows.length === 0 ? (
        <p className="mt-3 text-xs text-muted">{emptyLabel}</p>
      ) : (
        <div className="mt-3 space-y-2">
          {rows.map((row) => (
            <div key={row.label} className="flex items-center justify-between gap-3 text-xs">
              <span className="truncate text-muted">{row.label}</span>
              <span className="font-semibold text-ink">{row.value}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
