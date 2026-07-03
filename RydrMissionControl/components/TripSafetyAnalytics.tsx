import { adminDb } from "@/lib/firebaseAdmin";
import { toDateSafe } from "@/lib/format";

type SubjectKind = "driver" | "rider";

type Coordinate = { lat: number; lng: number };

type RideRecord = {
  id: string;
  driverId?: string;
  riderId?: string;
  driverName?: string;
  riderName?: string;
  pickup?: string;
  dropoff?: string;
  stop?: string;
  status?: string;
  rideType?: string;
  pickupCoordinate?: unknown;
  pickupGeoPoint?: unknown;
  dropoffCoordinate?: unknown;
  dropoffGeoPoint?: unknown;
  stopCoordinate?: unknown;
  stopGeoPoint?: unknown;
  acceptedAt?: { toDate?: () => Date } | null;
  arrivedAtPickupAt?: { toDate?: () => Date } | null;
  rideStartedAt?: { toDate?: () => Date } | null;
  startedAt?: { toDate?: () => Date } | null;
  completedAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
};

type TelemetryPoint = {
  lat?: number;
  lng?: number;
  speed?: number;
  status?: string;
  recordedAt?: { toDate?: () => Date } | null;
};

type RideSafetySummary = {
  ride: RideRecord;
  telemetryCount: number;
  longStopSignals: number;
  offRouteSamples: number;
  pickupWaitMinutes: number | null;
  tripMinutes: number | null;
  telemetryAvailable: boolean;
};

export default async function TripSafetyAnalytics({ uid, kind }: { uid: string; kind: SubjectKind }) {
  const rides = await loadRides(uid, kind);
  const summaries = await Promise.all(rides.slice(0, 12).map(summarizeRide));
  const telemetryReady = summaries.some((summary) => summary.telemetryAvailable);
  const totalLongStops = summaries.reduce((sum, summary) => sum + summary.longStopSignals, 0);
  const totalOffRoute = summaries.reduce((sum, summary) => sum + summary.offRouteSamples, 0);
  const completed = summaries.filter((summary) => summary.ride.status === "completed").length;

  return (
    <section className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-sm font-semibold text-ink">Trip Safety Analytics</h2>
          <p className="mt-1 text-xs text-muted">
            Recent ride timing and route signals for safety review. Route deviation and unscheduled-stop checks require trip telemetry.
          </p>
        </div>
        <Badge tone={telemetryReady ? "ok" : "warn"}>{telemetryReady ? "Telemetry active" : "Telemetry pending"}</Badge>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Metric label="Recent rides" value={summaries.length} />
        <Metric label="Completed" value={completed} />
        <Metric label="Long-stop signals" value={totalLongStops} tone={totalLongStops > 0 ? "warn" : "default"} />
        <Metric label="Off-route samples" value={totalOffRoute} tone={totalOffRoute > 0 ? "warn" : "default"} />
      </div>

      {!telemetryReady && (
        <p className="mt-4 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
          Existing rides may not have route telemetry. New driver builds now record throttled trip points during active rides.
        </p>
      )}

      <div className="mt-4 overflow-hidden rounded-md border border-line">
        <table className="w-full text-sm">
          <thead className="border-b border-line bg-grouped text-left text-xs font-medium text-muted">
            <tr>
              <th className="px-3 py-2">Ride</th>
              <th className="px-3 py-2">Trip time</th>
              <th className="px-3 py-2">Pickup wait</th>
              <th className="px-3 py-2">Telemetry</th>
              <th className="px-3 py-2">Signals</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {summaries.map((summary) => (
              <tr key={summary.ride.id}>
                <td className="px-3 py-2">
                  <p className="font-medium text-ink">
                    {summary.ride.pickup ?? "Pickup"} to {summary.ride.dropoff ?? "Drop-off"}
                  </p>
                  <p className="mt-0.5 text-[11px] text-muted">
                    {[summary.ride.rideType, summary.ride.status].filter(Boolean).join(" · ") || summary.ride.id}
                  </p>
                </td>
                <td className="px-3 py-2 text-muted">{formatMinutes(summary.tripMinutes)}</td>
                <td className="px-3 py-2 text-muted">{formatMinutes(summary.pickupWaitMinutes)}</td>
                <td className="px-3 py-2 text-muted">{summary.telemetryAvailable ? `${summary.telemetryCount} points` : "Not recorded"}</td>
                <td className="px-3 py-2">
                  <div className="flex flex-wrap gap-1.5">
                    <Badge tone={summary.longStopSignals > 0 ? "warn" : "neutral"}>{summary.longStopSignals} long stops</Badge>
                    <Badge tone={summary.offRouteSamples > 0 ? "warn" : "neutral"}>{summary.offRouteSamples} off route</Badge>
                  </div>
                </td>
              </tr>
            ))}
            {summaries.length === 0 && (
              <tr>
                <td colSpan={5} className="px-3 py-6 text-center text-muted">
                  No rides found for this {kind}.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}

async function loadRides(uid: string, kind: SubjectKind): Promise<RideRecord[]> {
  const field = kind === "driver" ? "driverId" : "riderId";
  const snap = await adminDb.collection("rides").where(field, "==", uid).limit(50).get().catch(() => null);
  if (!snap) return [];
  return snap.docs
    .map((doc) => ({ ...(doc.data() as RideRecord), id: doc.id }))
    .sort((a, b) => (rideTimestamp(b)?.getTime() ?? 0) - (rideTimestamp(a)?.getTime() ?? 0));
}

async function summarizeRide(ride: RideRecord): Promise<RideSafetySummary> {
  const telemetrySnap = await adminDb
    .collection("rides")
    .doc(ride.id)
    .collection("telemetry")
    .orderBy("recordedAt", "asc")
    .limit(500)
    .get()
    .catch(() => null);
  const points = telemetrySnap?.docs.map((doc) => doc.data() as TelemetryPoint) ?? [];
  const pickup = coordinate(ride.pickupCoordinate) ?? coordinate(ride.pickupGeoPoint);
  const dropoff = coordinate(ride.dropoffCoordinate) ?? coordinate(ride.dropoffGeoPoint);
  const stop = coordinate(ride.stopCoordinate) ?? coordinate(ride.stopGeoPoint);

  return {
    ride,
    telemetryCount: points.length,
    longStopSignals: longStopSignals(points, [pickup, stop, dropoff].filter(Boolean) as Coordinate[]),
    offRouteSamples: offRouteSamples(points, pickup, stop, dropoff),
    pickupWaitMinutes: minutesBetween(toDateSafe(ride.arrivedAtPickupAt), toDateSafe(ride.rideStartedAt) ?? toDateSafe(ride.startedAt)),
    tripMinutes: minutesBetween(toDateSafe(ride.rideStartedAt) ?? toDateSafe(ride.startedAt), toDateSafe(ride.completedAt)),
    telemetryAvailable: points.length > 0
  };
}

function longStopSignals(points: TelemetryPoint[], knownStops: Coordinate[]) {
  let count = 0;
  let stationaryStart: Date | null = null;
  let stationaryPoint: Coordinate | null = null;

  for (const point of points) {
    const at = toDateSafe(point.recordedAt);
    const coord = coordinate(point);
    if (!at || !coord) continue;
    const speed = typeof point.speed === "number" && point.speed >= 0 ? point.speed : null;
    const stationary = speed === null ? false : speed < 1.5;

    if (stationary && !stationaryStart) {
      stationaryStart = at;
      stationaryPoint = coord;
    } else if (!stationary && stationaryStart) {
      if (stationaryPoint && minutesBetween(stationaryStart, at)! >= 5 && !nearAny(stationaryPoint, knownStops, 0.15)) {
        count += 1;
      }
      stationaryStart = null;
      stationaryPoint = null;
    }
  }
  return count;
}

function offRouteSamples(points: TelemetryPoint[], pickup: Coordinate | null, stop: Coordinate | null, dropoff: Coordinate | null) {
  if (!pickup || !dropoff) return 0;
  const segments = stop ? [[pickup, stop], [stop, dropoff]] : [[pickup, dropoff]];
  let count = 0;
  for (const point of points) {
    const coord = coordinate(point);
    if (!coord) continue;
    const nearest = Math.min(...segments.map(([from, to]) => distanceToSegmentMiles(coord, from, to)));
    if (nearest > 0.75) count += 1;
  }
  return count;
}

function coordinate(value: unknown): Coordinate | null {
  if (!value || typeof value !== "object") return null;
  const data = value as { lat?: unknown; lng?: unknown; latitude?: unknown; longitude?: unknown };
  const lat = typeof data.lat === "number" ? data.lat : typeof data.latitude === "number" ? data.latitude : null;
  const lng = typeof data.lng === "number" ? data.lng : typeof data.longitude === "number" ? data.longitude : null;
  return lat == null || lng == null ? null : { lat, lng };
}

function distanceToSegmentMiles(point: Coordinate, start: Coordinate, end: Coordinate) {
  const centerLat = ((start.lat + end.lat) / 2) * (Math.PI / 180);
  const xy = (coord: Coordinate) => ({
    x: coord.lng * 69 * Math.cos(centerLat),
    y: coord.lat * 69
  });
  const p = xy(point);
  const a = xy(start);
  const b = xy(end);
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  if (dx === 0 && dy === 0) return distanceMiles(point, start);
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)));
  const projection = { x: a.x + t * dx, y: a.y + t * dy };
  return Math.hypot(p.x - projection.x, p.y - projection.y);
}

function distanceMiles(a: Coordinate, b: Coordinate) {
  const earthRadiusMiles = 3958.8;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 2 * earthRadiusMiles * Math.asin(Math.sqrt(h));
}

function nearAny(point: Coordinate, stops: Coordinate[], miles: number) {
  return stops.some((stop) => distanceMiles(point, stop) <= miles);
}

function rideTimestamp(ride: RideRecord) {
  return toDateSafe(ride.completedAt) ?? toDateSafe(ride.updatedAt) ?? toDateSafe(ride.acceptedAt);
}

function minutesBetween(start: Date | null, end: Date | null) {
  if (!start || !end) return null;
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
}

function formatMinutes(value: number | null) {
  return value == null ? "—" : `${value} min`;
}

function Metric({ label, value, tone = "default" }: { label: string; value: string | number; tone?: "default" | "warn" }) {
  return (
    <div className="rounded-md border border-line bg-grouped px-3 py-2">
      <p className="text-[11px] font-medium text-muted">{label}</p>
      <p className={`mt-1 text-lg font-semibold ${tone === "warn" ? "text-amber-700" : "text-ink"}`}>{value}</p>
    </div>
  );
}

function Badge({ tone, children }: { tone: "ok" | "warn" | "neutral"; children: React.ReactNode }) {
  const styles =
    tone === "ok" ? "bg-emerald-50 text-emerald-700" : tone === "warn" ? "bg-amber-50 text-amber-700" : "bg-grouped text-muted";
  return <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${styles}`}>{children}</span>;
}
