import Link from "next/link";
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
    return "Unavailable";
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
    driversOnline,
  ] = await Promise.all([
    count("drivers", (q) => q.where("driverApprovalStatus", "==", "pending")),
    count("drivers", (q) =>
      q.where("driverApprovalStatus", "==", "needs_attention"),
    ),
    count("drivers", (q) => q.where("driverApprovalStatus", "==", "approved")),
    count("safetyReports", (q) => q.where("status", "==", "open")),
    count("riders", (q) => q.where("verifiedRider", "==", true)),
    count("driverApprovalRequests"),
    count("driver_status", (q) => q.where("isOnline", "==", true)),
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
        <p className="mt-1 text-sm text-muted">
          Your operations at a glance. Choose a workspace to take action.
        </p>
      </div>

      <section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-red-500 via-pink-600 to-indigo-600 p-6 text-white sm:p-8">
        <p className="text-xs font-semibold uppercase tracking-[.18em] text-white/75">
          Rydr operations
        </p>
        <h2 className="mt-3 text-2xl font-semibold tracking-tight">
          A clear view. A smoother ride.
        </h2>
        <p className="mt-2 max-w-xl text-sm text-white/85">
          Keep people moving with focused reviews, timely support, and a
          complete view of your fleet.
        </p>
        <div className="mt-6 flex flex-wrap gap-3">
          {[
            ["/drivers", "Review drivers"],
            ["/support", "Open support inbox"],
            ["/analytics", "Explore analytics"],
          ].map(([href, label]) => (
            <Link
              key={href}
              href={href}
              className="rounded-xl border border-white/30 bg-white/15 px-4 py-2.5 text-xs font-semibold backdrop-blur hover:bg-white/25"
            >
              {label} ↗
            </Link>
          ))}
        </div>
      </section>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        <Link href="/drivers" className="transition hover:-translate-y-0.5">
          <StatCard
            label="Pending Driver Reviews"
            value={pendingDriverReviews}
            tone="warning"
          />
        </Link>
        <Link href="/drivers" className="transition hover:-translate-y-0.5">
          <StatCard
            label="Needs Attention"
            value={needsAttention}
            tone="warning"
          />
        </Link>
        <Link href="/drivers/all" className="transition hover:-translate-y-0.5">
          <StatCard
            label="Approved Drivers"
            value={approvedDrivers}
            tone="good"
          />
        </Link>
        <Link href="/reports" className="transition hover:-translate-y-0.5">
          <StatCard
            label="Open Safety Cases"
            value={openReports}
            tone="danger"
          />
        </Link>
        <Link href="/riders" className="transition hover:-translate-y-0.5">
          <StatCard label="Verified Riders" value={verifiedRiders} />
        </Link>
        <Link
          href="/beta-testers"
          className="transition hover:-translate-y-0.5"
        >
          <StatCard label="Beta Drivers (in pipeline)" value={betaDrivers} />
        </Link>
        <Link href="/drivers/all" className="transition hover:-translate-y-0.5">
          <StatCard
            label="Drivers Online Now"
            value={driversOnline}
            tone="good"
          />
        </Link>
      </div>

      <div className="rounded-lg border border-line bg-white shadow-sm">
        <div className="border-b border-line px-5 py-3">
          <h2 className="text-sm font-semibold text-ink">Recent Activity</h2>
        </div>
        <div className="divide-y divide-line">
          {recentActivity && !recentActivity.empty ? (
            recentActivity.docs.map((doc) => {
              const data = doc.data();
              const ts = data.createdAt?.toDate
                ? data.createdAt.toDate()
                : null;
              return (
                <div
                  key={doc.id}
                  className="flex items-center justify-between px-5 py-3 text-sm"
                >
                  <div>
                    <span className="font-medium text-ink">{data.action}</span>
                    <span className="ml-2 text-muted">
                      {data.targetType} · {data.targetId}
                    </span>
                  </div>
                  <span className="text-xs text-muted">
                    {ts ? ts.toLocaleString() : ""}
                  </span>
                </div>
              );
            })
          ) : (
            <p className="px-5 py-6 text-center text-sm text-muted">
              No admin actions recorded yet. Approvals, rejections, and report
              actions will show up here.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
