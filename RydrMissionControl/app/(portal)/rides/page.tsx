import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { WorkspaceLink as Link } from "@/components/WorkspaceContext";
import DataTable from "@/components/DataTable";
import StatusPill from "@/components/StatusPill";
import { toDateSafe } from "@/lib/format";
export const dynamic = "force-dynamic";
export default async function RidesPage() {
  const snap = await (await getWorkspaceDb())
    .collection("rides")
    .orderBy("updatedAt", "desc")
    .limit(200)
    .get();
  return (
    <div className="space-y-6">
      <div>
        <p className="mc-eyebrow mb-2">Ride operations</p>
        <h1>Rides</h1>
        <p className="mt-2 text-sm text-muted">
          Recent trips in this workspace. Open a ride to review its participants
          and fare.
        </p>
      </div>
      <DataTable
        label="rides"
        columns={["Ride", "Status", "Ride type", "Rider", "Driver", "Updated"]}
        rows={snap.docs.map((doc) => {
          const r = doc.data();
          const updated = toDateSafe(r.updatedAt);
          return {
            id: doc.id,
            search: [doc.id, r.status, r.rideType, r.riderId, r.driverId].join(
              " ",
            ),
            values: [
              doc.id,
              r.status ?? "",
              r.rideType ?? "",
              r.riderId ?? "",
              r.driverId ?? "",
              updated?.getTime() ?? 0,
            ],
            cells: [
              <Link
                key="ride"
                className="font-semibold text-rydr-burgundy"
                href={`/rides/${doc.id}`}
              >
                {doc.id.slice(0, 18)} ↗
              </Link>,
              <StatusPill key="status" status={r.status ?? "unknown"} />,
              r.rideType ?? "—",
              r.riderId ? (
                <Link key="rider" href={`/riders/${r.riderId}`}>
                  Rider profile ↗
                </Link>
              ) : (
                "—"
              ),
              r.driverId ? (
                <Link key="driver" href={`/drivers/${r.driverId}`}>
                  Driver profile ↗
                </Link>
              ) : (
                "—"
              ),
              updated?.toLocaleString("en-US", {
                timeZone: "America/New_York",
              }) ?? "—",
            ],
          };
        })}
      />
      <p className="text-xs text-muted">
        Up to 200 most recently updated rides are loaded.
      </p>
    </div>
  );
}
