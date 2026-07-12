import Link from "next/link";
import StatusPill from "@/components/StatusPill";
import { campusGrowthAnalytics, campusGrowthCounts, listOutreachDrafts } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";

export const dynamic = "force-dynamic";

const SECTIONS = [
  { href: "/campus-growth/discovery", title: "AI Discovery", body: "Start a search, review AI matches, and approve usable leads.", action: "Find leads" },
  { href: "/campus-growth/outreach", title: "Outreach Inbox", body: "Review drafts before any message leaves support@rydr-go.com.", action: "Review drafts" },
  { href: "/campus-growth/organizations", title: "Organizations", body: "Approved clubs, departments, chapters, and incubators.", action: "Open CRM" },
  { href: "/campus-growth/events", title: "Events", body: "Career fairs, hackathons, student events, and partnership moments.", action: "Open events" },
  { href: "/campus-growth/ambassadors", title: "Ambassadors", body: "Track people and groups that can help recruit riders, drivers, and interns.", action: "Track prospects" },
  { href: "/campus-growth/campuses", title: "Campuses", body: "Target markets, campus owners, priorities, and notes.", action: "Manage schools" }
];

export default async function CampusGrowthPage() {
  const [counts, analytics, drafts] = await Promise.all([campusGrowthCounts(), campusGrowthAnalytics(), listOutreachDrafts(8)]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h1 className="text-xl font-semibold text-ink">Campus Growth</h1>
          <p className="mt-1 text-sm text-muted">
            AI-assisted campus lead discovery, review, outreach drafts, and ambassador recruiting.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/campus-growth/discovery" className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white">
            Ask AI to Find Leads
          </Link>
          <Link href="/campus-growth/outreach" className="rounded-md border border-line bg-white px-4 py-2 text-xs font-semibold text-ink">
            Open Outreach Inbox
          </Link>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
        <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-sm font-semibold text-ink">Campus Agent Workflow</h2>
              <p className="mt-1 text-xs text-muted">Discovery stays public-source only. Outreach stays human-approved.</p>
            </div>
            <StatusPill status={counts.pendingDiscoveredLeads > 0 ? "pending_review" : "active"} label={counts.pendingDiscoveredLeads > 0 ? "Review needed" : "Ready"} />
          </div>
          <Link href="/campus-growth/discovery" className="mt-4 flex items-center justify-between gap-4 rounded-md border border-ink bg-ink px-4 py-3 text-white">
            <div>
              <p className="text-sm font-semibold">Start here: run an AI lead search</p>
              <p className="mt-1 text-xs text-white/75">Enter a search goal, choose campuses, then click Run AI Search.</p>
            </div>
            <span className="rounded-md bg-white px-3 py-1.5 text-xs font-semibold text-ink">Open</span>
          </Link>
          <div className="mt-3 grid gap-3 md:grid-cols-4">
            <WorkflowStep index="1" title="Search" body="Tell AI what lead type support outreach needs." href="/campus-growth/discovery" />
            <WorkflowStep index="2" title="Review" body="Approve strong matches or reject weak/private-source results." href="/campus-growth/discovery" />
            <WorkflowStep index="3" title="Draft" body="Create outreach drafts for email, org social, events, internships, or ambassadors." href="/campus-growth/outreach" />
            <WorkflowStep index="4" title="Track" body="Move approved leads into organizations, events, and ambassador follow-up." href="/campus-growth/organizations" />
          </div>
        </div>

        <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
          <h2 className="text-sm font-semibold text-ink">Today&apos;s Work Queue</h2>
          <div className="mt-4 space-y-3">
            <QueueRow label="AI leads waiting for review" value={counts.pendingDiscoveredLeads} href="/campus-growth/discovery" />
            <QueueRow label="Outreach drafts pending approval" value={counts.pendingDrafts} href="/campus-growth/outreach" />
            <QueueRow label="Ambassador prospects identified" value={analytics.ambassadorProspects} href="/campus-growth/ambassadors" />
            <QueueRow label="Intern prospects identified" value={analytics.internProspects} href="/campus-growth/organizations" />
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-7">
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
            <div className="flex items-start justify-between gap-3">
              <h2 className="text-sm font-semibold text-ink">{section.title}</h2>
              <span className="rounded-md bg-grouped px-2 py-1 text-[11px] font-semibold text-ink">{section.action}</span>
            </div>
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

function WorkflowStep({ index, title, body, href }: { index: string; title: string; body: string; href: string }) {
  return (
    <Link href={href} className="rounded-md border border-line bg-grouped p-3 hover:border-ink">
      <div className="flex h-7 w-7 items-center justify-center rounded-full bg-ink text-xs font-semibold text-white">{index}</div>
      <h3 className="mt-3 text-sm font-semibold text-ink">{title}</h3>
      <p className="mt-1 text-xs leading-5 text-muted">{body}</p>
    </Link>
  );
}

function QueueRow({ label, value, href }: { label: string; value: number; href: string }) {
  return (
    <Link href={href} className="flex items-center justify-between gap-3 rounded-md border border-line px-3 py-2 hover:border-ink">
      <span className="text-xs font-medium text-muted">{label}</span>
      <span className={`text-sm font-semibold ${value > 0 ? "text-ink" : "text-muted"}`}>{value}</span>
    </Link>
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
