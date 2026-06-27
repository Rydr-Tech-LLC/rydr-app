import { adminDb } from "@/lib/firebaseAdmin";
import type { DriverRecord, RiderRecord } from "@/lib/types";
import { fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";

export const dynamic = "force-dynamic";

export default async function BetaTestersPage() {
  const [driverSnap, riderSnap] = await Promise.all([
    adminDb.collection("drivers").limit(500).get(),
    adminDb.collection("riders").limit(500).get()
  ]);

  const drivers = driverSnap.docs.map((doc) => ({ uid: doc.id, ...(doc.data() as DriverRecord) }));
  const riders = riderSnap.docs.map((doc) => ({ uid: doc.id, ...(doc.data() as RiderRecord) }));

  const approvedDrivers = drivers.filter((d) => d.driverApprovalStatus === "approved");
  const pendingDrivers = drivers.filter((d) => !d.driverApprovalStatus || d.driverApprovalStatus === "pending" || d.driverApprovalStatus === "needs_attention");
  const removedDrivers = drivers.filter((d) => d.driverApprovalStatus === "rejected");
  const approvedRiders = riders.filter((r) => (r.accountStatus ?? "active") === "active");
  const verifiedRiders = riders.filter((r) => r.verifiedRider);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-xl font-semibold text-ink">Beta Testers</h1>
        <p className="mt-1 text-sm text-muted">Cohort breakdown across drivers and riders.</p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <Tile label="Approved Beta Drivers" value={approvedDrivers.length} />
        <Tile label="Pending Drivers" value={pendingDrivers.length} />
        <Tile label="Removed Drivers" value={removedDrivers.length} />
        <Tile label="Approved Riders" value={approvedRiders.length} />
        <Tile label="Verified Riders" value={verifiedRiders.length} />
      </div>

      <Group title="Approved Drivers" rows={approvedDrivers.map((d) => ({ id: d.uid, name: fullName(d.firstName, d.lastName), meta: d.email }))} />
      <Group title="Pending Drivers" rows={pendingDrivers.map((d) => ({ id: d.uid, name: fullName(d.firstName, d.lastName), meta: d.email }))} />
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

function Group({ title, rows }: { title: string; rows: { id: string; name: string; meta?: string }[] }) {
  return (
    <div className="rounded-lg border border-line bg-white shadow-sm">
      <div className="border-b border-line px-5 py-3">
        <h2 className="text-sm font-semibold text-ink">{title}</h2>
      </div>
      <div className="divide-y divide-line">
        {rows.length === 0 ? (
          <p className="px-5 py-4 text-sm text-muted">None.</p>
        ) : (
          rows.map((row) => (
            <div key={row.id} className="flex items-center justify-between px-5 py-2.5 text-sm">
              <span className="font-medium text-ink">{row.name}</span>
              <span className="text-xs text-muted">{row.meta ?? "—"}</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
