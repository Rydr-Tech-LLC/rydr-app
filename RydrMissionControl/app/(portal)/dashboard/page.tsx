import { adminDb } from "@/lib/firebaseAdmin";
import StatCard from "@/components/StatCard";

export const dynamic = "force-dynamic";

async function count(collection: string, filter?: (q: any) => any) {
  try {
    let ref: any = adminDb.collection(collection);
    if (filter) ref = filter(ref);
    const snap = await ref.count().get();
    return snap.data().count as number;
  } catch {
    return 0;
  }
}

export default async function DashboardPage() {
  const [
    pendingDriverReviews,
    needsAttention,
    approvedDrivers,
    openReports,
    verifiedRiders,
    betaDrivers,
    driversOnline
  ] = await Promise.all([
    count("drivers", (q) => q.where("driverApprovalStatus", "==", "pending")),
    count("drivers", (q) => q.where("driverApprovalStatus", "==", "needs_attention")),
    count("drivers", (q) => q.where("driverApprovalStatus", "==", "approved")),
    count("safetyReports", (q) => q.where("status", "==", "open")),
    count("riders", (q) => q.where("verifiedRider", "==", true)),
    count("driverApprovalRequests"),
    count("driver_status", (q) => q.where("isOnline", "==", true))
  ]);

  const recentActivity = await adminDb
    .collection("audits")
    .orderBy("createdAt", "desc")
    .limit(8)
    .get()
    .catch(() => null);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-xl font-semibold text-ink">Dashboard</h1>
        <p className="mt-1 text-sm text-muted">Platform overview, live from Firestore.</p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        <StatCard label="Pending Driver Reviews" value={pendingDriverReviews} tone="warning" />
        <StatCard label="Needs Attention" value={needsAttention} tone="warning" />
        <StatCard label="Approved Drivers" value={approvedDrivers} tone="good" />
        <StatCard label="Open Safety Cases" value={openReports} tone="danger" />
        <StatCard label="Verified Riders" value={verifiedRiders} />
        <StatCard label="Beta Drivers (in pipeline)" value={betaDrivers} />
        <StatCard label="Drivers Online Now" value={driversOnline} tone="good" />
      </div>

      <div className="rounded-lg border border-line bg-white shadow-sm">
        <div className="border-b border-line px-5 py-3">
          <h2 className="text-sm font-semibold text-ink">Recent Activity</h2>
        </div>
        <div className="divide-y divide-line">
          {recentActivity && !recentActivity.empty ? (
            recentActivity.docs.map((doc) => {
              const data = doc.data();
              const ts = data.createdAt?.toDate ? data.createdAt.toDate() : null;
              return (
                <div key={doc.id} className="flex items-center justify-between px-5 py-3 text-sm">
                  <div>
                    <span className="font-medium text-ink">{data.action}</span>
                    <span className="ml-2 text-muted">
                      {data.targetType} · {data.targetId}
                    </span>
                  </div>
                  <span className="text-xs text-muted">{ts ? ts.toLocaleString() : ""}</span>
                </div>
              );
            })
          ) : (
            <p className="px-5 py-6 text-center text-sm text-muted">
              No admin actions recorded yet. Approvals, rejections, and report actions will show up here.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
