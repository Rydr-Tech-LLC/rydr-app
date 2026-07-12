import StatusPill from "@/components/StatusPill";
import { listAmbassadors, listCampuses } from "@/lib/campusGrowth";
import { timeAgo, toDateSafe } from "@/lib/format";
import { AmbassadorForm } from "../CampusGrowthForms";

export const dynamic = "force-dynamic";

export default async function CampusAmbassadorsPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const [campuses, ambassadorsRaw] = await Promise.all([listCampuses(250), listAmbassadors(500)]);
  const ambassadors = filter(ambassadorsRaw, query, ["name", "email", "campusName", "notes", "status"]);

  return (
    <div className="space-y-6">
      <Header title="Campus Ambassadors" body="Track prospects who can help recruit interns, riders, and drivers." />
      <AmbassadorForm campuses={campuses} />
      <SearchBox placeholder="Search ambassadors, campuses, status..." />
      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        {ambassadors.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No ambassador candidates found.</p>
        ) : (
          <div className="divide-y divide-line">
            {ambassadors.map((ambassador) => (
              <div key={ambassador.id} className="px-5 py-4">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium text-ink">{ambassador.name}</p>
                  <StatusPill status={ambassador.status ?? "prospect"} />
                </div>
                <p className="mt-1 text-xs text-muted">
                  {ambassador.email} · {ambassador.campusName || "Unassigned campus"} · Updated {timeAgo(toDateSafe(ambassador.updatedAt))}
                </p>
                {ambassador.goals?.length ? <p className="mt-1 text-xs text-muted">Goals: {ambassador.goals.join(", ")}</p> : null}
                {ambassador.notes && <p className="mt-2 text-xs leading-5 text-muted">{ambassador.notes}</p>}
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
