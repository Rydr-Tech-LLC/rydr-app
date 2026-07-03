import { adminDb } from "@/lib/firebaseAdmin";
import { toDateSafe } from "@/lib/format";
import StatCard from "@/components/StatCard";

export const dynamic = "force-dynamic";

type RideAnalyticsRecord = {
  id: string;
  status?: string;
  paymentStatus?: string;
  rideType?: string;
  fare?: number;
  estimatedFare?: number;
  finalRiderChargeCents?: number;
  estimatedRiderTotalCents?: number;
  estimatedPlatformShareCents?: number;
  tipAmountCents?: number;
  completedAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
  createdAt?: { toDate?: () => Date } | null;
};

type PresenceEvent = {
  driverId?: string;
  isOnline?: boolean;
  createdAt?: { toDate?: () => Date } | null;
};

export default async function AnalyticsPage() {
  const [rides, presenceEvents, onlineDrivers] = await Promise.all([
    loadRecentRides(),
    loadPresenceEvents(),
    countOnlineDrivers()
  ]);

  const now = new Date();
  const windowStart = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const completed = rides.filter((ride) => ride.status === "completed");
  const paid = rides.filter((ride) => ride.paymentStatus === "succeeded");
  const grossCents = paid.reduce((sum, ride) => sum + riderChargeCents(ride), 0);
  const platformCents = paid.reduce((sum, ride) => sum + platformShareCents(ride), 0);
  const tipsCents = paid.reduce((sum, ride) => sum + cents(ride.tipAmountCents), 0);
  const ridesPerMinute = completed.length / Math.max(1, Math.round((now.getTime() - windowStart.getTime()) / 60000));
  const onlineMinutes = calculateOnlineMinutes(presenceEvents, windowStart, now);
  const rideTypeCounts = groupCounts(completed.map((ride) => ride.rideType ?? "Unknown"));
  const paymentCounts = groupCounts(rides.map((ride) => ride.paymentStatus ?? "unknown"));
  const dailyRevenue = dailyBuckets(paid, windowStart, now);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-xl font-semibold text-ink">Analytics</h1>
        <p className="mt-1 text-sm text-muted">
          Live beta metrics from Firestore. Online-time history begins when updated driver apps start writing presence events.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard label="Completed rides" value={completed.length} tone="good" />
        <StatCard label="Rides per minute" value={ridesPerMinute.toFixed(3)} />
        <StatCard label="Drivers online now" value={onlineDrivers} tone={onlineDrivers > 0 ? "good" : "default"} />
        <StatCard label="Tracked online hours" value={(onlineMinutes / 60).toFixed(1)} />
        <StatCard label="Gross rider charges" value={currency(grossCents)} tone="good" />
        <StatCard label="Platform share" value={currency(platformCents)} tone="good" />
        <StatCard label="Driver tips" value={currency(tipsCents)} />
        <StatCard label="Paid rides" value={paid.length} />
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <Panel title="Revenue by Day">
          <BarSeries
            points={dailyRevenue.map((bucket) => ({
              label: bucket.label,
              value: bucket.grossCents,
              secondaryValue: bucket.platformCents
            }))}
            valueFormatter={currency}
          />
        </Panel>

        <Panel title="Ride Mix">
          <MetricList items={rideTypeCounts} emptyText="No completed rides in this window." />
        </Panel>

        <Panel title="Payment Status">
          <MetricList items={paymentCounts} emptyText="No ride payment records found." />
        </Panel>

        <Panel title="Reporting Notes">
          <div className="space-y-3 text-sm text-muted">
            <p>
              Crowdfunding and lender reports should use gross rider charges, platform share, completed ride volume,
              repeat rider counts, paid ride rate, driver supply, and safety/support case resolution time.
            </p>
            <p>
              Historical driver online time requires `driverPresenceEvents`. This page now reads that collection; older
              sessions before this instrumentation will not have duration data.
            </p>
          </div>
        </Panel>
      </div>
    </div>
  );
}

async function loadRecentRides(): Promise<RideAnalyticsRecord[]> {
  const snap = await adminDb.collection("rides").orderBy("updatedAt", "desc").limit(500).get().catch(() => null);
  if (!snap) return [];
  return snap.docs.map((doc) => ({ ...(doc.data() as RideAnalyticsRecord), id: doc.id }));
}

async function loadPresenceEvents(): Promise<PresenceEvent[]> {
  const snap = await adminDb.collection("driverPresenceEvents").orderBy("createdAt", "desc").limit(2000).get().catch(() => null);
  if (!snap) return [];
  return snap.docs.map((doc) => doc.data() as PresenceEvent);
}

async function countOnlineDrivers() {
  const snap = await adminDb.collection("driver_status").where("isOnline", "==", true).count().get().catch(() => null);
  return snap?.data().count ?? 0;
}

function cents(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
}

function riderChargeCents(ride: RideAnalyticsRecord) {
  return cents(ride.finalRiderChargeCents) || cents(ride.estimatedRiderTotalCents) || Math.round((ride.fare ?? ride.estimatedFare ?? 0) * 100);
}

function platformShareCents(ride: RideAnalyticsRecord) {
  return cents(ride.estimatedPlatformShareCents);
}

function rideDate(ride: RideAnalyticsRecord) {
  return toDateSafe(ride.completedAt) ?? toDateSafe(ride.updatedAt) ?? toDateSafe(ride.createdAt);
}

function groupCounts(values: string[]) {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return Array.from(counts.entries())
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}

function dailyBuckets(rides: RideAnalyticsRecord[], start: Date, end: Date) {
  const buckets: { label: string; grossCents: number; platformCents: number }[] = [];
  for (let cursor = startOfDay(start); cursor <= end; cursor = addDays(cursor, 1)) {
    buckets.push({ label: `${cursor.getMonth() + 1}/${cursor.getDate()}`, grossCents: 0, platformCents: 0 });
  }
  for (const ride of rides) {
    const date = rideDate(ride);
    if (!date || date < start || date > end) continue;
    const index = Math.floor((startOfDay(date).getTime() - startOfDay(start).getTime()) / 86400000);
    if (buckets[index]) {
      buckets[index].grossCents += riderChargeCents(ride);
      buckets[index].platformCents += platformShareCents(ride);
    }
  }
  return buckets;
}

function calculateOnlineMinutes(events: PresenceEvent[], start: Date, end: Date) {
  const byDriver = new Map<string, { online: boolean; at: Date }[]>();
  for (const event of events) {
    const driverId = event.driverId;
    const at = toDateSafe(event.createdAt);
    if (!driverId || !at) continue;
    const list = byDriver.get(driverId) ?? [];
    list.push({ online: event.isOnline === true, at });
    byDriver.set(driverId, list);
  }

  let minutes = 0;
  for (const eventsForDriver of byDriver.values()) {
    const sorted = eventsForDriver.sort((a, b) => a.at.getTime() - b.at.getTime());
    let onlineAt: Date | null = null;
    for (const event of sorted) {
      if (event.online) {
        onlineAt = event.at;
      } else if (onlineAt) {
        minutes += overlapMinutes(onlineAt, event.at, start, end);
        onlineAt = null;
      }
    }
    if (onlineAt) minutes += overlapMinutes(onlineAt, end, start, end);
  }
  return minutes;
}

function overlapMinutes(from: Date, to: Date, windowStart: Date, windowEnd: Date) {
  const start = Math.max(from.getTime(), windowStart.getTime());
  const end = Math.min(to.getTime(), windowEnd.getTime());
  return Math.max(0, (end - start) / 60000);
}

function startOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date: Date, days: number) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);
}

function currency(valueCents: number) {
  return (valueCents / 100).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="text-sm font-semibold text-ink">{title}</h2>
      <div className="mt-4">{children}</div>
    </section>
  );
}

function BarSeries({
  points,
  valueFormatter
}: {
  points: { label: string; value: number; secondaryValue?: number }[];
  valueFormatter: (value: number) => string;
}) {
  const max = Math.max(1, ...points.map((point) => point.value));
  return (
    <div className="space-y-2">
      {points.slice(-14).map((point) => (
        <div key={point.label} className="grid grid-cols-[3rem_1fr_6rem] items-center gap-3 text-xs">
          <span className="text-muted">{point.label}</span>
          <div className="h-7 overflow-hidden rounded-md bg-grouped">
            <div className="h-full rounded-md bg-rydr-burgundy" style={{ width: `${Math.max(2, (point.value / max) * 100)}%` }} />
          </div>
          <span className="text-right font-medium text-ink">{valueFormatter(point.value)}</span>
        </div>
      ))}
    </div>
  );
}

function MetricList({ items, emptyText }: { items: { label: string; value: number }[]; emptyText: string }) {
  if (items.length === 0) return <p className="text-sm text-muted">{emptyText}</p>;
  const max = Math.max(...items.map((item) => item.value), 1);
  return (
    <div className="space-y-3">
      {items.map((item) => (
        <div key={item.label}>
          <div className="mb-1 flex items-center justify-between text-xs">
            <span className="font-medium text-ink">{item.label}</span>
            <span className="text-muted">{item.value}</span>
          </div>
          <div className="h-2 rounded-full bg-grouped">
            <div className="h-2 rounded-full bg-ink" style={{ width: `${(item.value / max) * 100}%` }} />
          </div>
        </div>
      ))}
    </div>
  );
}
