import DeclineDocumentForm from "./DeclineDocumentForm";
import RerunDocumentReview from "./RerunDocumentReview";
import { DOCUMENT_REJECTION_LABELS } from "../../../../../rydr-backend/firebase/functions/src/services/documentReviewFeedback";
import ImageViewer from "@/components/ImageViewer";
import { driverDocumentReviewItems, uploadedDocumentPath } from "@/lib/driverDocumentReview";
import { toDateSafe } from "@/lib/format";

const fields = {
  driverLicense: {
    documentType: "Detected document", licenseClass: "Class", state: "Issuing state",
    issuanceDate: "Issue date", expirationDate: "Expiration date", licenseNumber: "License number"
  },
  insurance: {
    insurancePolicyNumber: "Policy number", effectiveDate: "Effective date", expirationDate: "End date",
    policyholderFirstName: "Policyholder first name", policyholderLastName: "Policyholder last name",
    vin: "VIN", vehicleYear: "Year", vehicleMake: "Make", vehicleModel: "Model"
  },
  registration: {
    vin: "VIN", vehicleMake: "Make", vehicleModel: "Model", vehicleYear: "Year", expirationDate: "Expiration date"
  },
  vehicleInspection: { expirationDate: "Expiration date", vin: "VIN", plateNumber: "License plate" }
};

const labels: Record<string, string> = { approved: "Approved", pending: "Automated review processing", needs_review: "Manual review required", rejected: "Rejected — needs attention", expired: "Expired", awaiting_automation: "Uploaded — review result missing", missing: "Not uploaded" };
export default function DriverDocumentReviewPanel({ uid, driver, history }: { uid: string; driver: any; history: any[] }) {
  const items = driverDocumentReviewItems(driver);
  return <section id="document-review" className="scroll-mt-6 space-y-4 rounded-3xl border border-line bg-white p-5">
    <div className="rounded-2xl bg-gradient-to-r from-red-50 via-fuchsia-50 to-blue-50 p-4"><h2 className="text-lg font-semibold">Uploaded documents & automated review</h2><p className="mt-1 text-sm text-muted">Uploads are recorded by the backend. Automated checks run first; uncertain or failed checks stay here for manual review. A replacement awaiting review does not erase an older approved document.</p></div>
    <div className="grid gap-4 lg:grid-cols-2">{items.filter(item => item.kind !== "vehicleInspection" || item.uploaded).map(item => {
      const record = item.record;
      const previews = (["front", "back"] as const).filter(side => uploadedDocumentPath(driver, uid, item.kind, side));
      const reviewed = toDateSafe(record.automationReviewedAt ?? record.reviewedAt);
      const canRead = item.kind !== "vehicleInspection" && !item.processing
        && uploadedDocumentPath(driver, uid, item.kind, item.kind === "driverLicense" ? "front" : "single");
      const legacyOcr = item.kind !== "vehicleInspection" && record.extractedFields && record.ocrSchemaVersion !== 2;
      const ocrFields = legacyOcr ? {} : record.extractedFields ?? {};
      const verifiedExpiry = record.approvedRecord?.expirationDate;
      const expiryDisagrees = record.manualReviewId === record.reviewId && record.manualReviewId
        && typeof verifiedExpiry === "string" && ocrFields.expirationDate && verifiedExpiry !== ocrFields.expirationDate;
      return <article key={item.kind} className="rounded-2xl border border-line p-4"><div className="flex flex-wrap items-center justify-between gap-2"><h3 className="font-semibold">{item.label}</h3><span className={`rounded-full px-3 py-1 text-xs font-medium ${item.attention ? "bg-amber-100 text-amber-900" : item.status === "approved" ? "bg-emerald-50 text-emerald-800" : "bg-grouped text-muted"}`}>{labels[item.status] ?? item.status}</span></div>
        <p className="mt-2 text-sm text-muted">{record.reviewReason || (item.uploaded ? "The upload is available. Automated review details will appear here." : "No upload has been recorded.")}</p>
        <div className="mt-3 grid grid-cols-2 gap-2">{previews.map(side => <ImageViewer key={side} label={`${item.label} ${side}`} url={`/api/drivers/${encodeURIComponent(uid)}/documents/${item.kind}/${side}`} />)}</div>
        {legacyOcr && !item.processing && <p className="mt-2 text-xs text-muted">Re-run automated review to refresh fields from this upload.</p>}
        {item.uploaded && !item.processing && item.status !== "awaiting_automation" && <dl className="mt-3 grid grid-cols-2 gap-2 text-xs">
          {Object.entries(fields[item.kind]).map(([key, label]) => {
            const value = ocrFields[key];
            return <div key={key}><dt className="text-muted">{label}</dt><dd className={value ? "break-words font-medium" : "text-muted"}>
              {key === "documentType" && value === "driverLicense" ? "Driver’s license" : value || "Not detected"}
            </dd></div>;
          })}
        </dl>}
        {expiryDisagrees && <p className="mt-2 rounded-lg bg-amber-50 p-2 text-xs text-amber-900">
          The OCR expiration date differs from the staff-verified date ({verifiedExpiry}). Check the upload before updating the verified date.
        </p>}
        {record.automationStatus && record.manualReviewId && record.manualReviewId === record.reviewId &&
          <p className="mt-2 text-xs text-muted">{labels[record.automationStatus] ?? record.automationStatus}. {record.automationReason}</p>}
        {canRead && <RerunDocumentReview uid={uid} kind={item.kind} reviewId={record.reviewId ?? ""} />}
        {record.storagePath && <DeclineDocumentForm uid={uid} kind={item.kind} storagePath={record.storagePath} reviewId={record.reviewId ?? ""} reasons={DOCUMENT_REJECTION_LABELS} />}
        {reviewed && <p className="mt-2 text-xs text-muted">Reviewed {reviewed.toLocaleString("en-US", { timeZone: "America/New_York" })} ET</p>}
        {record.approvedRecord && item.status !== "approved" && <p className="mt-2 rounded-lg bg-grouped p-2 text-xs">Previous approved proof retained. Its validity and driving holds are evaluated separately.</p>}
      </article>;
    })}</div>
    <details className="rounded-xl border border-line p-3"><summary className="cursor-pointer text-sm font-medium">Recent automated review history ({history.length})</summary><ul className="mt-3 space-y-2 text-sm">{history.map(review => <li key={review.id} className="rounded-lg bg-grouped p-3"><strong>{review.documentType} · {labels[review.status] ?? review.status}</strong><p>{review.reviewReason}</p>{review.checks && <p className="mt-1 text-xs text-muted">{Object.entries(review.checks).map(([key, value]) => `${key}: ${String(value)}`).join(" · ")}</p>}</li>)}</ul></details>
  </section>;
}
