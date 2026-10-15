import DataTable from "@/components/DataTable";
import Link from "next/link";
import StatusPill from "@/components/StatusPill";
import {
  listCampuses,
  listOrganizations,
  listOutreachDrafts,
} from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";
import { OutreachDraftForm } from "../CampusGrowthForms";
import OutreachActions from "./OutreachActions";

export const dynamic = "force-dynamic";

export default async function CampusOutreachPage(props: {
  searchParams: Promise<{ q?: string }>;
}) {
  const searchParams = await props.searchParams;
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const [campuses, organizations, draftsRaw] = await Promise.all([
    listCampuses(250),
    listOrganizations(500),
    listOutreachDrafts(500),
  ]);
  const drafts = filter(draftsRaw, query, [
    "subject",
    "campusName",
    "organizationName",
    "recipientName",
    "recipientEmail",
    "body",
    "status",
  ]);
  const pending = draftsRaw.filter(
    (draft) => (draft.status ?? "draft") === "draft",
  ).length;
  const approved = draftsRaw.filter(
    (draft) => draft.status === "approved",
  ).length;
  const sent = draftsRaw.filter((draft) => draft.status === "sent").length;
  const replied = draftsRaw.filter(
    (draft) => draft.status === "replied",
  ).length;

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted">
            <Link
              href="/campus-growth"
              className="font-semibold text-ink hover:underline"
            >
              Campus Growth
            </Link>
            <span>/</span>
            <span>Outreach Inbox</span>
          </div>
          <h1 className="mt-3 text-2xl font-semibold text-ink">
            Outreach Draft Approvals
          </h1>
          <p className="mt-1 text-sm text-muted">
            Review Rydr-letterhead drafts, approve them, send email through
            Resend, or mark manually sent.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            href="/campus-growth/discovery"
            className="rounded-md bg-gradient-to-r from-rydr-red to-rydr-burgundy px-4 py-2 text-xs font-semibold text-white shadow-sm"
          >
            Find Leads with AI
          </Link>
          <Link
            href="/campus-growth"
            className="rounded-md border border-line bg-white px-4 py-2 text-xs font-semibold text-ink shadow-sm"
          >
            Back to Dashboard
          </Link>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-4">
        <MetricCard
          label="Pending Approval"
          value={pending}
          helper="Drafts awaiting review"
          tone="amber"
        />
        <MetricCard
          label="Approved"
          value={approved}
          helper="Ready for manual send"
          tone="green"
        />
        <MetricCard
          label="Sent"
          value={sent}
          helper="Sent through Resend or marked sent"
          tone="red"
        />
        <MetricCard
          label="Replies"
          value={replied}
          helper="Marked replied"
          tone="purple"
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-[0.95fr_1.05fr]">
        <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-ink">
                How This Queue Works
              </h2>
              <p className="mt-1 text-sm text-muted">
                Mission Control controls approval. Resend delivers approved
                email messages.
              </p>
            </div>
            <StatusPill
              status={pending > 0 ? "pending_review" : "active"}
              label={pending > 0 ? "Review Needed" : "Clear"}
            />
          </div>
          <div className="mt-5 grid gap-3 md:grid-cols-3">
            <ProcessCard
              index="1"
              title="Approve Draft"
              body="Confirms the message is ready, but does not send it."
            />
            <ProcessCard
              index="2"
              title="Approve & Send"
              body="Sends email through Resend using Rydr letterhead and BCC policy."
            />
            <ProcessCard
              index="3"
              title="Mark Sent Manually"
              body="Use for non-email channels or messages sent outside Mission Control."
            />
          </div>
          <p className="mt-4 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs leading-5 text-muted">
            Email sends from support@rydr-go.com by default, BCCs
            khris.nunnally@rydr-go.com, and always uses the Rydr letterhead
            template.
          </p>
        </div>

        <details>
          <summary className="cursor-pointer rounded-lg border border-line bg-white px-5 py-4 text-base font-semibold text-ink shadow-sm">
            Add Manual Draft
          </summary>
          <div className="mt-3">
            <OutreachDraftForm
              campuses={campuses}
              organizations={organizations}
            />
          </div>
        </details>
      </div>

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <div className="flex flex-col gap-3 border-b border-line px-5 py-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <h2 className="text-base font-semibold text-ink">Draft Queue</h2>
            <p className="mt-1 text-xs text-muted">
              Every message remains human-reviewed before send or manual
              closeout.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <SearchBox placeholder="Search drafts..." />
            <span className="rounded-md bg-grouped px-3 py-2 text-xs font-semibold text-muted">
              {drafts.length} drafts
            </span>
          </div>
        </div>

        <DataTable
          label="outreach drafts"
          columns={[
            "Draft",
            "Recipient",
            "Channel",
            "Status",
            "Created",
            "Actions",
          ]}
          rows={drafts.map((draft) => ({
            id: draft.id,
            search: [
              draft.subject,
              draft.body,
              draft.organizationName,
              draft.recipientEmail,
              draft.campusName,
              draft.status,
              draft.channel,
            ].join(" "),
            values: [
              draft.subject ?? "",
              draft.organizationName ?? draft.recipientName ?? "",
              draft.channel ?? "",
              draft.status ?? "draft",
              toDateSafe(draft.createdAt)?.getTime() ?? 0,
              "",
            ],
            cells: [
              <div key="draft">
                <p className="font-semibold">
                  {draft.subject || "Untitled draft"}
                </p>
                <details className="mt-2 max-w-md">
                  <summary className="cursor-pointer text-xs text-rydr-burgundy">
                    Read message
                  </summary>
                  <p className="mt-3 whitespace-pre-wrap text-sm leading-relaxed text-muted">
                    {draft.body || "No body"}
                  </p>
                </details>
                {draft.denialReason && (
                  <p className="mt-2 text-xs text-red-700">
                    {draft.denialReason}
                  </p>
                )}
              </div>,
              <div key="recipient">
                <p className="font-medium">
                  {draft.organizationName ||
                    draft.recipientName ||
                    "Unassigned lead"}
                </p>
                <p className="mt-1 text-xs text-muted">
                  {draft.recipientEmail || "—"}
                </p>
                <p className="mt-1 text-xs text-muted">
                  {draft.campusName || "—"}
                </p>
              </div>,
              formatChannel(draft.channel),
              <StatusPill key="status" status={draft.status ?? "draft"} />,
              timeAgo(toDateSafe(draft.createdAt)),
              <OutreachActions
                key="actions"
                id={draft.id}
                status={draft.status ?? "draft"}
              />,
            ],
          }))}
        />
        <p className="border-t border-line px-5 py-3 text-xs text-muted">
          Email sends require explicit approval. Non-email channels are recorded
          manually after sending outside Mission Control.
        </p>
      </div>
    </div>
  );
}

function MetricCard({
  label,
  value,
  helper,
  tone,
}: {
  label: string;
  value: number;
  helper: string;
  tone: "amber" | "green" | "red" | "purple";
}) {
  const styles = {
    amber: "bg-amber-50 text-amber-700",
    green: "bg-emerald-50 text-emerald-700",
    red: "bg-red-50 text-rydr-red",
    purple: "bg-purple-50 text-purple-700",
  };
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-semibold text-muted">{label}</p>
          <p className="mt-2 text-3xl font-semibold text-ink">{value}</p>
          <p className="mt-1 text-xs text-muted">{helper}</p>
        </div>
        <span
          className={`rounded-full px-3 py-1 text-xs font-semibold ${styles[tone]}`}
        >
          {label.split(" ")[0]}
        </span>
      </div>
    </div>
  );
}

function ProcessCard({
  index,
  title,
  body,
}: {
  index: string;
  title: string;
  body: string;
}) {
  return (
    <div className="rounded-md border border-line bg-grouped p-3">
      <span className="flex h-7 w-7 items-center justify-center rounded-full bg-ink text-xs font-semibold text-white">
        {index}
      </span>
      <h3 className="mt-3 text-sm font-semibold text-ink">{title}</h3>
      <p className="mt-1 text-xs leading-5 text-muted">{body}</p>
    </div>
  );
}

function SearchBox({ placeholder }: { placeholder: string }) {
  return (
    <form className="flex gap-2">
      <input
        name="q"
        placeholder={placeholder}
        className="w-full rounded-md border border-line bg-white px-3 py-2 text-xs text-ink outline-none focus:border-rydr-red sm:w-64"
      />
      <button className="rounded-md border border-line bg-white px-3 py-2 text-xs font-semibold text-ink">
        Search
      </button>
    </form>
  );
}

function formatChannel(channel?: string) {
  if (!channel) return "Email";
  return channel
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function filter<T extends object>(
  items: T[],
  query: string,
  keys: Array<keyof T>,
): T[] {
  if (!query) return items;
  return items.filter((item) =>
    keys.some((key) =>
      String(item[key] ?? "")
        .toLowerCase()
        .includes(query),
    ),
  );
}
