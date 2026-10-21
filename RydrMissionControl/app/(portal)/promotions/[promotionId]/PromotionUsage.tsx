import { getWorkspaceDb } from "@/lib/firebaseAdmin";
export default async function PromotionUsage({
  promotionId,
  perUserLimit,
  type,
}: {
  promotionId: string;
  perUserLimit: number | null;
  type: string;
}) {
  const db = await getWorkspaceDb();
  const [usage, progress, redemptions, rewards] = await Promise.all([
    db.collection("promotionUsage").doc(promotionId).get(),
    db
      .collection("promotionProgress")
      .where("promotionId", "==", promotionId)
      .limit(100)
      .get(),
    db
      .collection("promotionRedemptions")
      .where("promotionId", "==", promotionId)
      .limit(100)
      .get(),
    db
      .collection("promotionRewards")
      .where("promotionId", "==", promotionId)
      .limit(100)
      .get(),
  ]);
  const milestone = type.endsWith("milestone_reward");
  return (
    <section className="rounded-2xl border border-line bg-white p-5 space-y-3">
      <h2 className="text-lg font-semibold">
        Account usage &amp; reward tracking
      </h2>
      <p className="text-sm text-muted">
        {Number(usage.data()?.issuedCount) || 0}{" "}
        {milestone ? "rewards issued" : "uses committed"} campaign-wide.
        Committed uses include payment reservations, so retries cannot overrun
        the limit.
      </p>
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-line">
              <th className="p-2">Account</th>
              <th className="p-2">Qualifying rides</th>
              <th className="p-2">
                {milestone ? "Rewards issued" : "Used or reserved"}
              </th>
              <th className="p-2">Remaining</th>
              <th className="p-2">State</th>
            </tr>
          </thead>
          <tbody>
            {progress.docs.map((d) => {
              const p = d.data();
              const issued = Number(p.issuedCount) || 0;
              const remaining =
                perUserLimit == null
                  ? null
                  : Math.max(0, perUserLimit - issued);
              return (
                <tr key={d.id} className="border-b border-line">
                  <td className="p-2 font-mono text-xs">{String(p.userId)}</td>
                  <td className="p-2">{Number(p.eligibleRideCount) || 0}</td>
                  <td className="p-2">{issued}</td>
                  <td className="p-2">{remaining ?? "No account cap"}</td>
                  <td className="p-2">
                    {remaining === 0
                      ? "Exhausted"
                      : "Subject to campaign terms"}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {!progress.size && (
        <p className="text-sm text-muted">
          No uses or qualifying rides recorded yet.
        </p>
      )}
      <details>
        <summary className="cursor-pointer text-sm font-semibold">
          Ride redemptions &amp; earned rewards
        </summary>
        <div className="mt-3 space-y-2 text-xs">
          {redemptions.docs.map((d) => {
            const r = d.data();
            return (
              <p key={d.id}>
                Account {String(r.userId ?? r.riderId ?? r.driverId)} · ride{" "}
                {String(r.rideId)} · {String(r.status)} · $
                {(
                  (Number(r.discountCents ?? r.rewardCents) || 0) / 100
                ).toFixed(2)}
              </p>
            );
          })}
          {rewards.docs.map((d) => {
            const r = d.data();
            return (
              <p key={d.id}>
                Account {String(r.userId)} · earned reward {String(r.status)}
                {r.reservedRideId ? ` · reserved on ${r.reservedRideId}` : ""}
                {r.usedRideId ? ` · used on ${r.usedRideId}` : ""}
              </p>
            );
          })}
        </div>
      </details>
      <p className="text-xs text-muted">
        Shows up to 100 records per category. Remaining counts represent
        campaign uses or reward grants; earned rewards have separate
        availability and expiration.
      </p>
    </section>
  );
}
