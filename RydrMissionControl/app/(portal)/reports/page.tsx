import { adminDb } from "@/lib/firebaseAdmin";
import type { SafetyReport } from "@/lib/types";
import { toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import ReportActions from "./ReportActions";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const snap = await adminDb.collection("safetyReports").orderBy("createdAt", "desc").limit(200).get().catch(() => null);
  const reports = snap ? snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as SafetyReport) })) : [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Safety Reports</h1>
        <p className="mt-1 text-sm text-muted">Reports submitted by riders and drivers. The future moderation center.</p>
      </div>

      {reports.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center text-sm text-muted">
          No reports yet. Note: the apps don't currently persist incident reports server-side (see beta
          readiness audit, item #11) — this queue will populate once that's wired up.
        </div>
      ) : (
        <div className="space-y-2">
          {reports.map((report) => {
            const created = toDateSafe(report.createdAt);
            return (
              <div key={report.id} className="rounded-lg border border-line bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-ink">{report.reportType ?? "Report"}</p>
                      <StatusPill status={report.status} />
                    </div>
                    <p className="mt-0.5 text-xs text-muted">
                      Ride {report.rideId ?? "—"} · Driver {report.driverName ?? report.driverId ?? "—"} · Rider{" "}
                      {report.riderName ?? report.riderId ?? "—"} · {created ? created.toLocaleString() : "—"}
                    </p>
                    {report.description && <p className="mt-2 text-sm text-ink">{report.description}</p>}
                  </div>
                </div>
                <div className="mt-3">
                  <ReportActions id={report.id} hasDriver={Boolean(report.driverId)} hasRider={Boolean(report.riderId)} />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
