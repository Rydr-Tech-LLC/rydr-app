import StatusPill from "@/components/StatusPill";
import { listCampusEvents, listCampuses } from "@/lib/campusGrowth";
import { toDateSafe } from "@/lib/format";
import { EventForm } from "../CampusGrowthForms";

export const dynamic = "force-dynamic";

export default async function CampusEventsPage({ searchParams }: { searchParams: { q?: string } }) {
  const query = (searchParams.q ?? "").toLowerCase().trim();
  const [campuses, eventsRaw] = await Promise.all([listCampuses(250), listCampusEvents(500)]);
  const events = filter(eventsRaw, query, ["name", "campusName", "venue", "category", "source", "notes"]);

  return (
    <div className="space-y-6">
      <Header title="Campus Event Leads" body="Public event opportunities for outreach and ambassador recruiting." />
      <EventForm campuses={campuses} />
      <SearchBox placeholder="Search events, campuses, venues..." />
      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        {events.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No event leads found.</p>
        ) : (
          <div className="divide-y divide-line">
            {events.map((event) => {
              const startsAt = toDateSafe(event.startsAt);
              return (
                <div key={event.id} className="px-5 py-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium text-ink">{event.name}</p>
                    <StatusPill status={event.status ?? "new"} />
                    <StatusPill status="qualified" label={`Score ${event.opportunityScore ?? 0}`} />
                  </div>
                  <p className="mt-1 text-xs text-muted">
                    {event.campusName || "Unassigned campus"} · {event.venue || "No venue"} · {startsAt ? startsAt.toLocaleString() : "No date"} ·{" "}
                    {event.source || "public source"}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {event.priorityLevel && <StatusPill status={event.priorityLevel} label={`${event.priorityLevel} priority`} />}
                    {event.relationshipStrength && <StatusPill status="queued" label={event.relationshipStrength} />}
                    {event.discoveryConfidence ? <StatusPill status="qualified" label={`Confidence ${event.discoveryConfidence}`} /> : null}
                    {event.lastAIRecommendation && <StatusPill status="queued" label={event.lastAIRecommendation} />}
                  </div>
                  {event.tags?.length ? <p className="mt-2 text-xs text-muted">Tags: {event.tags.join(", ")}</p> : null}
                  {event.aiSummary && <p className="mt-2 text-xs leading-5 text-muted">{event.aiSummary}</p>}
                  {event.scoreReason && <p className="mt-2 rounded-md bg-blue-50 px-3 py-2 text-xs text-blue-800">{event.scoreReason}</p>}
                  {event.notes && <p className="mt-2 text-xs leading-5 text-muted">{event.notes}</p>}
                </div>
              );
            })}
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
