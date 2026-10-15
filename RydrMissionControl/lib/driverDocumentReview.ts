export const DRIVER_DOCUMENT_KINDS = ["driverLicense", "insurance", "registration", "vehicleInspection"] as const;
export type DriverDocumentKind = typeof DRIVER_DOCUMENT_KINDS[number];
export const DOCUMENT_LABELS: Record<DriverDocumentKind, string> = { driverLicense: "Driver license", insurance: "Insurance", registration: "Vehicle registration", vehicleInspection: "Vehicle inspection" };

export function latestDriverDocument(driver: any, kind: DriverDocumentKind): Record<string, any> {
  const record = { ...(driver.documents?.[kind] ?? (kind === "driverLicense" ? driver.documents?.license : null) ?? {}) };
  for (const field of ["status", "reviewReason", "reviewId", "storagePath", "frontPath", "backPath", "documentPath", "downloadURL", "frontURL", "backURL", "documentURL", "extractedFields", "reviewedAt"]) {
    record[field] ??= driver[`documents.${kind}.${field}`];
  }
  if (kind === "driverLicense") {
    record.frontPath ??= driver.licenseSubmission?.frontStoragePath;
    record.backPath ??= driver.licenseSubmission?.backStoragePath;
  } else if (kind === "insurance") record.documentPath ??= driver.vehicleDocumentSubmission?.insuranceStoragePath;
  else if (kind === "registration") record.documentPath ??= driver.vehicleDocumentSubmission?.registrationStoragePath;
  record.storagePath ??= record.documentPath ?? record.frontPath;
  return record;
}

export function uploadedDocumentPath(driver: any, uid: string, kind: string, side: string): string | null {
  if (!DRIVER_DOCUMENT_KINDS.includes(kind as DriverDocumentKind) || !["front", "back", "single"].includes(side)) return null;
  const record = latestDriverDocument(driver, kind as DriverDocumentKind);
  const path = side === "back" ? record.backPath : side === "front" ? record.frontPath ?? record.documentPath ?? (record.lastUploadedSide === "back" ? null : record.storagePath) : record.documentPath ?? record.storagePath ?? record.frontPath;
  if (typeof path !== "string" || !path.startsWith(`driverDocuments/${uid}/${kind}/`) || path.split("/").some(segment => segment === ".." || segment === ".")) return null;
  return path;
}

export function driverDocumentReviewItems(driver: any) {
  return DRIVER_DOCUMENT_KINDS.map(kind => {
    const record = latestDriverDocument(driver, kind);
    const uploaded = Boolean(record.storagePath || record.frontURL || record.documentURL || record.downloadURL || record.backURL);
    const status: string = record.status ?? (uploaded ? "awaiting_automation" : "missing");
    const attention = ["needs_review", "rejected", "expired", "awaiting_automation"].includes(status);
    return { kind, label: DOCUMENT_LABELS[kind], record, uploaded, status, attention, processing: status === "pending" };
  });
}
