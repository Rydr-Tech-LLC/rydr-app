import StatusPill from "@/components/StatusPill";
import { listCampuses, listOrganizations, listOutreachDrafts } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";
import { OutreachDraftForm } from "../CampusGrowthForms";
import OutreachActions from "./OutreachActions";

export const dynamic = "force-dynamic";

export default async function CampusOutreachPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const [campuses, organizations, draftsRaw] = await Promise.all([listCampuses(250), listOrganizations(500), listOutreachDrafts(500)]);
  const drafts = filter(draftsRaw, query, ["subject", "campusName", "organizationName", "recipientName", "recipientEmail", "body", "status"]);

  return (
    <div className="space-y-6">
      <Header title="Outreach Inbox" body="Create personalized drafts, then approve or deny before anything is sent." />
      <OutreachDraftForm campuses={campuses} organizations={organizations} />
      <SearchBox placeholder="Search drafts, recipients, campuses..." />
      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        {drafts.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No outreach drafts found.</p>
        ) : (
          <div className="divide-y divide-line">
            {drafts.map((draft) => (
              <div key={draft.id} className="grid gap-4 px-5 py-4 lg:grid-cols-[1fr_auto]">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium text-ink">{draft.subject ?? "Untitled draft"}</p>
                    <StatusPill status={draft.status ?? "draft"} />
                  </div>
                  <div className="mt-2 grid gap-1 text-xs text-muted md:grid-cols-2">
                    <span>From: {draft.fromEmail ?? "support@rydr-go.com"}</span>
                    <span>BCC: {draft.bccEmail ?? "khris.nunnally@rydr-go.com"}</span>
                    <span>To: {draft.recipientEmail || draft.recipientName || "-"}</span>
                    <span>Campus: {draft.campusName || "-"}</span>
                    <span>Organization: {draft.organizationName || "-"}</span>
                    <span>Created: {timeAgo(toDateSafe(draft.createdAt))}</span>
                  </div>
                  <p className="mt-3 max-h-24 overflow-hidden whitespace-pre-wrap text-xs leading-5 text-muted">{draft.body}</p>
                  {draft.denialReason && <p className="mt-2 rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">{draft.denialReason}</p>}
                </div>
                <OutreachActions id={draft.id} status={draft.status ?? "draft"} />
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
