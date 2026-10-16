import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { WorkspaceLink as Link } from "@/components/WorkspaceContext";
import DataTable from "@/components/DataTable";
import StatusPill from "@/components/StatusPill";
import { toDateSafe } from "@/lib/format";
export const dynamic = "force-dynamic";
export default async function DisputesPage() {
  const snap = await (await getWorkspaceDb())
    .collection("supportTickets")
    .orderBy("updatedAt", "desc")
    .limit(500)
    .get();
  const cases = snap.docs.filter((doc) => {
    const t = doc.data();
    return /disput|charge_issue|fare_issue|payment_issue/.test(
      [t.category, t.issueType, t.subject].join(" ").toLowerCase(),
    );
  });
  return (
    <div className="space-y-6">
      <div>
        <p className="mc-eyebrow mb-2">Fare & charge reviews</p>
        <h1>Disputes</h1>
        <p className="mt-2 text-sm text-muted">
          Investigate ride-charge disputes in this workspace. Open a
          conversation to review evidence, reply, or resolve the case.
        </p>
      </div>
      <DataTable
        label="disputes"
        columns={["Case", "Status", "Account", "Ride", "Updated"]}
        rows={cases.map((doc) => {
          const t = doc.data(),
            date = toDateSafe(t.updatedAt);
          return {
            id: doc.id,
            search: [t.subject, t.userId, t.rideId, t.status].join(" "),
            values: [
              t.subject ?? "",
              t.status ?? "open",
              t.userRole ?? "",
              t.rideId ?? "",
              date?.getTime() ?? 0,
            ],
            cells: [
              <Link
                key="case"
                className="font-semibold text-rydr-burgundy"
                href={`/support/${doc.id}`}
              >
                {t.subject ?? "Charge dispute"} ↗
              </Link>,
              <StatusPill key="status" status={t.status ?? "open"} />,
              t.userId ? (
                <Link
                  key="profile"
                  href={`/${t.userRole === "driver" ? "drivers" : "riders"}/${t.userId}`}
                >
                  Open {t.userRole ?? "rider"} ↗
                </Link>
              ) : (
                "—"
              ),
              t.rideId ? (
                <Link key="ride" href={`/rides/${t.rideId}`}>
                  Ride details ↗
                </Link>
              ) : (
                "—"
              ),
              date?.toLocaleString("en-US", { timeZone: "America/New_York" }) ??
                "—",
            ],
          };
        })}
      />
      <p className="text-xs text-muted">
        Search covers dispute cases within the 500 most recently updated support
        tickets.
      </p>
    </div>
  );
}
