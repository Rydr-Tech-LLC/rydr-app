import { adminDb } from "@/lib/firebaseAdmin";
import type { RiderRecord } from "@/lib/types";
import { fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";

export const dynamic = "force-dynamic";

export default async function RidersPage() {
  const snap = await adminDb.collection("riders").limit(500).get();
  const riders = snap.docs.map((doc) => ({ ...(doc.data() as RiderRecord), uid: doc.id }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Riders</h1>
        <p className="mt-1 text-sm text-muted">{riders.length} total riders.</p>
      </div>

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <table className="w-full text-sm">
          <thead className="border-b border-line bg-grouped text-left text-xs font-medium text-muted">
            <tr>
              <th className="px-4 py-2.5">Name</th>
              <th className="px-4 py-2.5">Contact</th>
              <th className="px-4 py-2.5">Rides</th>
              <th className="px-4 py-2.5">Verified</th>
              <th className="px-4 py-2.5">Account Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {riders.map((rider) => (
              <tr key={rider.uid} className="hover:bg-grouped/60">
                <td className="px-4 py-2.5 font-medium text-ink">{fullName(rider.firstName, rider.lastName)}</td>
                <td className="px-4 py-2.5 text-muted">{rider.email ?? rider.phoneNumber ?? "—"}</td>
                <td className="px-4 py-2.5 text-muted">{rider.rideCount ?? 0}</td>
                <td className="px-4 py-2.5">
                  {rider.verifiedRider ? (
                    <StatusPill status="verified" label="Verified" />
                  ) : (
                    <span className="text-xs text-muted">Unverified</span>
                  )}
                </td>
                <td className="px-4 py-2.5">
                  <StatusPill status={rider.accountStatus ?? "active"} />
                </td>
              </tr>
            ))}
            {riders.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-muted">
                  No riders yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
