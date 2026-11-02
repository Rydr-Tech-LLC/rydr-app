import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { WorkspaceLink as Link } from "@/components/WorkspaceContext";
import DataTable from "@/components/DataTable";
import StatusPill from "@/components/StatusPill";
import { toDateSafe } from "@/lib/format";
export const dynamic = "force-dynamic";
export default async function DisputesPage() {
  const db = await getWorkspaceDb();
  const financial = await db.collection("financialReviewCases").orderBy("updatedAt", "desc").limit(200).get();
  const snap = await db
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
      <section className="space-y-3">
        <h2 className="text-lg font-semibold">Stripe refunds and disputes</h2>
        <p className="text-sm text-muted">Review driver transfers and promotion accounting after a refund or bank dispute. Reviewing a case does not move money.</p>
        <DataTable label="Stripe financial reviews" columns={["Kind", "Status", "Amount", "Ride", "Follow-up"]}
          rows={financial.docs.map(doc => {
            const review = doc.data();
            const amount = Number(review.amountCents || 0);
            return { id: doc.id, search: [review.kind, review.status, review.rideId, review.stripeObjectId].join(" "),
              values: [review.kind, review.status, amount, review.rideId, review.driverTransferReviewRequired ? "Driver transfer review" : ""],
              cells: [review.kind === "refund" ? "Refund" : "Bank dispute", <StatusPill key="status" status={review.status || "open"} />,
                new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"}).format(amount / 100),
                <Link key="ride" href={`/rides/${review.rideId}`}>Ride details ↗</Link>,
                review.driverTransferReviewRequired ? "Review driver transfer and rewards" : "No driver transfer review required"] };
          })} />
      </section>
      <p className="text-xs text-muted">
        Search covers dispute cases within the 500 most recently updated support
        tickets.
      </p>
    </div>
  );
}
