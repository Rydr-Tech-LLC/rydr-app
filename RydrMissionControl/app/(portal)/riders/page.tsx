import DataTable from "@/components/DataTable";
import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import type { RiderRecord } from "@/lib/types";
import { fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";

export const dynamic = "force-dynamic";

export default async function RidersPage() {
  const snap = await (await getWorkspaceDb()).collection("riders").limit(500).get();
  const riders = snap.docs.map((doc) => ({
    ...(doc.data() as RiderRecord),
    uid: doc.id,
  }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Riders</h1>
        <p className="mt-1 text-sm text-muted">
          {riders.length} riders loaded · Search, sort, and open a profile.
        </p>
      </div>

      <DataTable
        label="riders"
        columns={[
          "Rider",
          "Contact",
          "Rides",
          "Verification",
          "Badges",
          "Account status",
        ]}
        rows={riders.map((r) => {
          const name = fullName(r.firstName, r.lastName);
          return {
            id: r.uid,
            search: [name, r.email, r.phoneNumber, r.uid, r.accountStatus].join(
              " ",
            ),
            values: [
              name,
              r.email ?? r.phoneNumber ?? "",
              r.rideCount ?? 0,
              r.verifiedRider ? "Verified" : "Unverified",
              r.badges?.studentAmbassador?.active ? "Ambassador" : "",
              r.accountStatus ?? "active",
            ],
            cells: [
              <Link
                key="name"
                href={`/riders/${r.uid}`}
                className="font-semibold hover:text-rydr-red"
              >
                {name}
              </Link>,
              r.email ?? r.phoneNumber ?? "—",
              r.rideCount ?? 0,
              <StatusPill
                key="verification"
                status={r.verifiedRider ? "verified" : "pending"}
                label={r.verifiedRider ? "Verified" : "Unverified"}
              />,
              r.badges?.studentAmbassador?.active ? (
                <StatusPill
                  key="badge"
                  status="active"
                  label="Student Ambassador"
                />
              ) : (
                "—"
              ),
              <StatusPill key="status" status={r.accountStatus ?? "active"} />,
            ],
          };
        })}
      />
    </div>
  );
}
