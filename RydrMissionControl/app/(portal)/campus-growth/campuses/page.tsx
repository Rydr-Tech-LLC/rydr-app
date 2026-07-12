import StatusPill from "@/components/StatusPill";
import { listCampuses } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";
import { CampusForm } from "../CampusGrowthForms";

export const dynamic = "force-dynamic";

export default async function CampusTargetsPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const campuses = filter(await listCampuses(250), query, ["name", "city", "state", "market", "owner", "notes"]);

  return (
    <div className="space-y-6">
      <Header title="Campus Targets" body="Markets and campuses to research, prioritize, and assign." />
      <CampusForm />
      <SearchBox placeholder="Search campuses, owners, markets..." />
      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        {campuses.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No campus targets found.</p>
        ) : (
          <div className="divide-y divide-line">
            {campuses.map((campus) => (
              <div key={campus.id} className="px-5 py-4">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium text-ink">{campus.name}</p>
                  <StatusPill status={campus.status ?? "researching"} />
                  <StatusPill status={campus.priority ?? "medium"} label={`${campus.priority ?? "medium"} priority`} />
                </div>
                <p className="mt-1 text-xs text-muted">
                  {[campus.city, campus.state, campus.market].filter(Boolean).join(" · ") || "No location"} · Owner: {campus.owner || "-"} · Updated{" "}
                  {timeAgo(toDateSafe(campus.updatedAt))}
                </p>
                {campus.notes && <p className="mt-2 text-xs leading-5 text-muted">{campus.notes}</p>}
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
