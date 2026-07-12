import Link from "next/link";
import StatusPill from "@/components/StatusPill";
import { campusGrowthAnalytics, campusGrowthCounts, listOutreachDrafts } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";

export const dynamic = "force-dynamic";

const SECTIONS = [
  { href: "/campus-growth/discovery", title: "AI Discovery", body: "Find and review public campus leads.", action: "Find leads", icon: "AI" },
  { href: "/campus-growth/outreach", title: "Outreach Inbox", body: "Approve drafts before anything is sent.", action: "Review", icon: "IN" },
  { href: "/campus-growth/organizations", title: "Organizations", body: "Manage approved clubs and departments.", action: "Open", icon: "OR" },
  { href: "/campus-growth/events", title: "Events", body: "Track events and partnership moments.", action: "Open", icon: "EV" },
  { href: "/campus-growth/ambassadors", title: "Ambassadors", body: "Track prospects and follow-up.", action: "Track", icon: "AM" },
  { href: "/campus-growth/campuses", title: "Campuses", body: "Manage target schools and priorities.", action: "Manage", icon: "CA" }
];

export default async function CampusGrowthPage() {
  const [counts, analytics, drafts] = await Promise.all([campusGrowthCounts(), campusGrowthAnalytics(), listOutreachDrafts(8)]);
  const discoveredTotal = analytics.organizationsDiscovered + analytics.eventsDiscovered;
  const contacted = analytics.funnel.find((row) => row.label === "Organizations")?.value ?? counts.organizations;
  const responded = analytics.funnel.find((row) => row.label === "Events")?.value ?? counts.events;

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-ink">Campus Growth</h1>
          <p className="mt-1 text-sm text-muted">
            AI-assisted lead discovery, review, outreach drafts, and ambassador recruiting.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            href="/campus-growth/discovery"
            className="rounded-md bg-gradient-to-r from-rydr-red to-rydr-burgundy px-4 py-2 text-xs font-semibold text-white shadow-sm"
          >
            Find Leads with AI
          </Link>
          <Link href="/campus-growth/outreach" className="rounded-md border border-line bg-white px-4 py-2 text-xs font-semibold text-ink shadow-sm">
            Open Outreach Inbox
          </Link>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="Campuses" value={counts.campuses} helper="Target schools in CRM" accent="red" icon="CA" />
        <MetricCard label="Leads Discovered" value={discoveredTotal} helper="AI and manual lead pipeline" accent="green" icon="LD" />
        <MetricCard label="Pending Review" value={counts.pendingDiscoveredLeads} helper="AI matches waiting for approval" accent="amber" icon="PR" />
        <MetricCard label="Outreach Drafts" value={counts.pendingDrafts} helper="Drafts requiring human approval" accent="purple" icon="OD" />
      </div>

      <div className="grid gap-4 xl:grid-cols-[1.35fr_1fr]">
        <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-ink">Campus Agent Workflow</h2>
              <p className="mt-1 text-sm text-muted">Discovery stays public-source only. Outreach stays human-approved.</p>
            </div>
            <StatusPill
              status={counts.pendingDiscoveredLeads > 0 ? "pending_review" : "active"}
              label={counts.pendingDiscoveredLeads > 0 ? "Review Needed" : "Agent Ready"}
            />
          </div>

          <Link
            href="/campus-growth/discovery"
            className="mt-4 flex flex-col gap-3 rounded-md border border-red-200 bg-red-50 px-4 py-3 text-ink hover:border-rydr-red sm:flex-row sm:items-center sm:justify-between"
          >
            <div>
              <p className="text-sm font-semibold">Start here: run an AI lead search</p>
              <p className="mt-1 text-xs text-muted">Describe the lead, select campuses, then click Run AI Search.</p>
            </div>
            <span className="w-fit rounded-md bg-rydr-red px-3 py-1.5 text-xs font-semibold text-white">Run AI Search</span>
          </Link>

          <div className="mt-5 grid gap-3 md:grid-cols-4">
            <WorkflowStep index="1" title="Search" value={discoveredTotal} label="found" tone="complete" href="/campus-growth/discovery" />
            <WorkflowStep index="2" title="Review" value={counts.pendingDiscoveredLeads} label="pending" tone="alert" href="/campus-growth/discovery" />
            <WorkflowStep index="3" title="Draft" value={counts.pendingDrafts} label="drafts" tone="warning" href="/campus-growth/outreach" />
            <WorkflowStep index="4" title="Track" value={analytics.ambassadorProspects} label="prospects" tone="info" href="/campus-growth/ambassadors" />
          </div>
        </div>

        <div className="rounded-lg border border-line bg-white shadow-sm">
          <div className="flex items-center justify-between border-b border-line px-5 py-4">
            <div>
              <h2 className="text-base font-semibold text-ink">Today&apos;s Work Queue</h2>
              <p className="mt-1 text-xs text-muted">Highest-priority campus growth actions.</p>
            </div>
          </div>
          <div className="divide-y divide-line">
            <QueueRow dot="bg-rydr-red" label="Review AI leads" detail="AI matches waiting for approval" value={counts.pendingDiscoveredLeads} href="/campus-growth/discovery" />
            <QueueRow dot="bg-amber-500" label="Approve outreach drafts" detail="Drafts pending human approval" value={counts.pendingDrafts} href="/campus-growth/outreach" />
            <QueueRow dot="bg-blue-500" label="Follow up with ambassadors" detail="Active prospects to engage" value={analytics.ambassadorProspects} href="/campus-growth/ambassadors" />
            <QueueRow dot="bg-purple-500" label="Review intern prospects" detail="Intern prospects awaiting review" value={analytics.internProspects} href="/campus-growth/organizations" />
          </div>
        </div>
      </div>

      <div className="grid gap-4 xl:grid-cols-[1.35fr_0.7fr_0.85fr]">
        <FunnelCard rows={[
          { label: "Discovered", value: discoveredTotal, color: "bg-red-400" },
          { label: "Approved", value: counts.approvedDiscoveredLeads, color: "bg-rydr-red" },
          { label: "Contacted", value: contacted, color: "bg-amber-400" },
          { label: "Responded", value: responded, color: "bg-emerald-500" }
        ]} />
        <RankCard title="Top Campuses" rows={analytics.topSchools} href="/campus-growth/campuses" emptyLabel="No schools yet" />
        <RankCard title="Top Categories" rows={analytics.topCategories} href="/campus-growth/organizations" emptyLabel="No categories yet" />
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-6">
        {SECTIONS.map((section) => (
          <Link key={section.href} href={section.href} className="rounded-lg border border-line bg-white p-4 shadow-sm hover:border-rydr-red">
            <div className="flex items-center justify-between gap-3">
              <IconBadge label={section.icon} tone="red" />
              <span className="text-lg text-muted">›</span>
            </div>
            <h2 className="mt-3 text-sm font-semibold text-ink">{section.title}</h2>
            <p className="mt-1 min-h-10 text-xs leading-5 text-muted">{section.body}</p>
            <p className="mt-3 text-xs font-semibold text-rydr-red">{section.action}</p>
          </Link>
        ))}
      </div>

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <h2 className="text-base font-semibold text-ink">Recent Outreach Drafts</h2>
          <Link href="/campus-growth/outreach" className="text-xs font-semibold text-rydr-red">
            View all drafts
          </Link>
        </div>
        {drafts.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">
            No drafts yet. Use AI Discovery to approve leads, then create outreach drafts for review.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-left text-xs">
              <thead className="border-b border-line bg-grouped text-muted">
                <tr>
                  <th className="px-5 py-3 font-semibold">Organization</th>
                  <th className="px-5 py-3 font-semibold">Campus</th>
                  <th className="px-5 py-3 font-semibold">Type</th>
                  <th className="px-5 py-3 font-semibold">Status</th>
                  <th className="px-5 py-3 font-semibold">Updated</th>
                  <th className="px-5 py-3 font-semibold">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {drafts.map((draft) => (
                  <tr key={draft.id} className="text-ink">
                    <td className="px-5 py-3 font-medium">{draft.organizationName || draft.recipientName || "Unassigned lead"}</td>
                    <td className="px-5 py-3 text-muted">{draft.campusName || "-"}</td>
                    <td className="px-5 py-3 text-muted">{formatChannel(draft.channel)}</td>
                    <td className="px-5 py-3">
                      <StatusPill status={draft.status ?? "draft"} />
                    </td>
                    <td className="px-5 py-3 text-muted">{timeAgo(toDateSafe(draft.createdAt))}</td>
                    <td className="px-5 py-3">
                      <Link href="/campus-growth/outreach" className="rounded-md border border-line bg-white px-3 py-1.5 font-semibold text-ink hover:border-ink">
                        Review
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="border-t border-line px-5 py-3 text-xs text-muted">
              No messages are auto-sent. Every outreach draft requires human approval.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function MetricCard({
  label,
  value,
  helper,
  accent,
  icon
}: {
  label: string;
  value: number;
  helper: string;
  accent: "red" | "green" | "amber" | "purple";
  icon: string;
}) {
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-semibold text-muted">{label}</p>
          <p className="mt-2 text-3xl font-semibold text-ink">{value}</p>
          <p className="mt-1 text-xs text-muted">{helper}</p>
        </div>
        <IconBadge label={icon} tone={accent} />
      </div>
    </div>
  );
}

function IconBadge({ label, tone }: { label: string; tone: "red" | "green" | "amber" | "purple" }) {
  const styles = {
    red: "bg-red-50 text-rydr-red",
    green: "bg-emerald-50 text-emerald-700",
    amber: "bg-amber-50 text-amber-700",
    purple: "bg-purple-50 text-purple-700"
  };
  return <span className={`flex h-10 w-10 items-center justify-center rounded-full text-xs font-bold ${styles[tone]}`}>{label}</span>;
}

function WorkflowStep({
  index,
  title,
  value,
  label,
  tone,
  href
}: {
  index: string;
  title: string;
  value: number;
  label: string;
  tone: "complete" | "alert" | "warning" | "info";
  href: string;
}) {
  const styles = {
    complete: "border-emerald-200 bg-emerald-50 text-emerald-700",
    alert: "border-red-200 bg-red-50 text-rydr-red",
    warning: "border-amber-200 bg-amber-50 text-amber-700",
    info: "border-blue-200 bg-blue-50 text-blue-700"
  };
  return (
    <Link href={href} className="rounded-md border border-line p-3 text-center hover:border-ink">
      <div className={`mx-auto flex h-10 w-10 items-center justify-center rounded-full border text-sm font-semibold ${styles[tone]}`}>{index}</div>
      <h3 className="mt-3 text-sm font-semibold text-ink">{title}</h3>
      <p className={`mt-1 text-xs font-semibold ${value > 0 ? "text-rydr-red" : "text-muted"}`}>
        {value} {label}
      </p>
    </Link>
  );
}

function QueueRow({ dot, label, detail, value, href }: { dot: string; label: string; detail: string; value: number; href: string }) {
  return (
    <Link href={href} className="grid grid-cols-[auto_1fr_auto_auto] items-center gap-3 px-5 py-3 hover:bg-grouped">
      <span className={`h-2.5 w-2.5 rounded-full ${dot}`} />
      <span>
        <span className="block text-sm font-medium text-ink">{label}</span>
        <span className="block text-xs text-muted">{detail}</span>
      </span>
      <span className={`text-lg font-semibold ${value > 0 ? "text-rydr-red" : "text-muted"}`}>{value}</span>
      <span className="text-lg text-muted">›</span>
    </Link>
  );
}

function FunnelCard({ rows }: { rows: Array<{ label: string; value: number; color: string }> }) {
  const max = Math.max(...rows.map((row) => row.value), 1);
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="text-base font-semibold text-ink">Lead Conversion Funnel</h2>
      <div className="mt-5 grid gap-4 md:grid-cols-4">
        {rows.map((row) => {
          const width = Math.max((row.value / max) * 100, row.value > 0 ? 8 : 0);
          return (
            <div key={row.label}>
              <p className="text-xs font-semibold text-muted">{row.label}</p>
              <p className="mt-1 text-2xl font-semibold text-ink">{row.value}</p>
              <div className="mt-3 h-2 rounded-full bg-grouped">
                <div className={`h-2 rounded-full ${row.color}`} style={{ width: `${width}%` }} />
              </div>
            </div>
          );
        })}
      </div>
      <p className="mt-5 border-t border-line pt-3 text-xs text-muted">Percentages scale against discovered leads and update as the CRM fills.</p>
    </div>
  );
}

function RankCard({ title, rows, href, emptyLabel }: { title: string; rows: Array<{ label: string; value: number }>; href: string; emptyLabel: string }) {
  const max = Math.max(...rows.map((row) => row.value), 1);
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="text-base font-semibold text-ink">{title}</h2>
      {rows.length === 0 ? (
        <p className="mt-5 text-sm text-muted">{emptyLabel}</p>
      ) : (
        <div className="mt-4 space-y-4">
          {rows.slice(0, 4).map((row) => (
            <div key={row.label}>
              <div className="flex items-center justify-between gap-3 text-xs">
                <span className="truncate font-medium text-ink">{row.label}</span>
                <span className="font-semibold text-muted">{row.value}</span>
              </div>
              <div className="mt-2 h-1.5 rounded-full bg-grouped">
                <div className="h-1.5 rounded-full bg-rydr-red" style={{ width: `${Math.max((row.value / max) * 100, 8)}%` }} />
              </div>
            </div>
          ))}
        </div>
      )}
      <Link href={href} className="mt-4 inline-block text-xs font-semibold text-rydr-red">
        View all
      </Link>
    </div>
  );
}

function formatChannel(channel?: string) {
  if (!channel) return "Outreach";
  return channel
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}
