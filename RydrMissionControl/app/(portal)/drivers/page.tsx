import { driverDocumentReviewItems } from "@/lib/driverDocumentReview";
import { evaluateDriverCompliance } from "../../../../rydr-backend/firebase/functions/src/services/driverCompliancePolicy";
import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { evaluateDriverRequirements, type DriverRecord } from "@/lib/types";
import { driverFullName, driverNameCollected, timeAgo, toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";

export const dynamic = "force-dynamic";

export default async function DriverVerificationQueuePage() {
  const [snap, policySnap] = await Promise.all([(await getWorkspaceDb()).collection("drivers").limit(300).get(), (await getWorkspaceDb()).collection("platformConfig").doc("driverCompliance").get()]);
  const policy = policySnap.data() ?? {};

  const queue = snap.docs
    .map((doc) => ({ ...(doc.data() as DriverRecord), uid: doc.id }))
    .filter((d) => {
      const status = d.driverApprovalStatus ?? "pending";
      const compliance = evaluateDriverCompliance(d, policy);
      return driverDocumentReviewItems(d).some(item => item.attention || item.processing) || status === "pending" || status === "needs_attention" || (status === "approved" && (!compliance.drivingAllowed || compliance.needsReviewKinds.length > 0 || compliance.expiringKinds.length > 0));
    })
    .sort((a, b) => {
      const aDate = toDateSafe(a.createdAt)?.getTime() ?? 0;
      const bDate = toDateSafe(b.createdAt)?.getTime() ?? 0;
      return bDate - aDate;
    });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Driver Verification Queue</h1>
        <p className="mt-1 text-sm text-muted">
          {queue.length} driver{queue.length === 1 ? "" : "s"} awaiting review.
        </p>
      </div>

      {queue.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center text-sm text-muted">
          No onboarding or document compliance items need review.
        </div>
      ) : (
        <div className="space-y-2">
          {queue.map((driver) => {
            const { checks, missing } = evaluateDriverRequirements(driver, policy);
            const compliance = evaluateDriverCompliance(driver, policy);
            const submitted = toDateSafe(driver.createdAt);
            return (
              <div
                key={driver.uid}
                className="flex items-center justify-between rounded-lg border border-line bg-white p-4 shadow-sm"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="font-medium text-ink">{driverFullName(driver)}</p>
                    <StatusPill status={driver.driverApprovalStatus ?? "pending"} />
                  </div>
                  <p className="mt-1 text-xs text-amber-700">{!compliance.drivingAllowed ? "Driving paused: current verified documents or screening required." : driverDocumentReviewItems(driver).some(item => item.attention) ? "Uploaded document requires review." : driverDocumentReviewItems(driver).some(item => item.processing) ? "Automated document review is processing." : compliance.needsReviewKinds.length ? "Document expiration dates need review." : compliance.expiringKinds.length ? "Documents expire within 30 days." : "Onboarding review"}</p>
                  {!driverNameCollected(driver) && (
                    <p className="mt-0.5 text-xs text-amber-700">Name/DOB onboarding step has not been completed.</p>
                  )}
                  <p className="mt-0.5 text-xs text-muted">Submitted: {timeAgo(submitted)}</p>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {driverDocumentReviewItems(driver).filter(item => item.attention || item.processing).map(item => <Link key={item.kind} href={`/drivers/${driver.uid}#document-review`} className="rounded-full bg-amber-100 px-2 py-1 text-xs text-amber-900">{item.label}: {item.processing ? "automated review processing" : "document review needed"}</Link>)}
                    {Object.entries(checks).map(([key, met]) => (
                      <span
                        key={key}
                        className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${
                          met ? "bg-emerald-50 text-emerald-700" : "bg-grouped text-muted"
                        }`}
                      >
                        {met ? "✓" : "•"}{" "}
                        {key.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase())}
                      </span>
                    ))}
                  </div>
                  {missing.length > 0 && (
                    <p className="mt-1.5 text-[11px] text-muted">Missing: {missing.join(", ")}</p>
                  )}
                </div>
                <Link
                  href={`/drivers/${driver.uid}`}
                  className="ml-4 flex-shrink-0 rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white hover:bg-ink/90"
                >
                  Review Driver
                </Link>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
