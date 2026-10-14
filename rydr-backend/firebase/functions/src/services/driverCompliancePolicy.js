// Standard driver compliance for beta and the open pilot. This policy does
// not depend on Executive qualification or alter financial-account access.
const DOCUMENT_KINDS = ['driverLicense', 'insurance', 'registration', 'vehicleInspection'];
const DOCUMENT_LABELS = { driverLicense: 'Driver license', insurance: 'Insurance', registration: 'Vehicle registration', vehicleInspection: 'Vehicle inspection' };
/** @param {any} value */
function timestamp(value) {
  if (!value) return NaN;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value.seconds != null) return Number(value.seconds) * 1000;
  return new Date(value).getTime();
}
/** @param {number} now */
function georgiaDate(now) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(now));
  const value = type => parts.find(part => part.type === type)?.value;
  return `${value('year')}-${value('month')}-${value('day')}`;
}
/** A date-only document stays valid through that entire Georgia calendar day.
 * @param {any} value */
function documentDeadline(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return timestamp(value);
  const day = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== value) return NaN;
  const nextDate = new Date(day.getTime() + 86400000).toISOString().slice(0, 10);
  const sample = new Date(`${nextDate}T05:00:00Z`);
  const offset = new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', timeZoneName: 'longOffset' }).formatToParts(sample).find(part => part.type === 'timeZoneName')?.value.replace('GMT', '') ?? '-05:00';
  return Date.parse(`${nextDate}T00:00:00${offset}`);
}
/** @param {any} driver @param {string} kind */
function currentDocument(driver, kind) {
  const nested = driver.documents?.[kind] ?? (kind === 'driverLicense' ? driver.documents?.license : null) ?? {};
  const record = { ...nested };
  // Read legacy dotted fields while new uploads use canonical nested maps.
  for (const field of ['status', 'extractedFields', 'storagePath', 'reviewId', 'approvedRecord']) {
    if (record[field] == null) record[field] = driver[`documents.${kind}.${field}`];
  }
  record.storagePath ??= record.documentPath ?? record.frontPath ?? (kind === 'driverLicense' ? driver.licenseSubmission?.frontStoragePath : kind === 'insurance' ? driver.vehicleDocumentSubmission?.insuranceStoragePath : kind === 'registration' ? driver.vehicleDocumentSubmission?.registrationStoragePath : undefined);
  if (!record.expirationDate && !record.extractedFields?.expirationDate) {
    record.expirationDate = kind === 'driverLicense' ? driver.driverLicenseExpiresAt ?? driver.licenseExpiresAt ?? driver.license?.expirationDate : kind === 'insurance' ? driver.insuranceExpiresAt ?? driver.vehicle?.insuranceExpiresAt : kind === 'registration' ? driver.registrationExpiresAt ?? driver.vehicle?.registrationExpiresAt : undefined;
  }
  return record.approvedRecord ?? record;
}
/** @param {any} driver @param {any} [config] @param {number} [now] */
function evaluateDriverCompliance(driver, config = {}, now = Date.now()) {
  const today = georgiaDate(now);
  const heldKinds = Array.isArray(driver.documentComplianceExpiredKinds) ? driver.documentComplianceExpiredKinds : [];
  const documentKinds = DOCUMENT_KINDS.filter(kind => kind !== "vehicleInspection" || Object.values(currentDocument(driver, kind)).some(value => value != null));
  const documents = documentKinds.map(kind => {
    const record = currentDocument(driver, kind);
    const expiry = record.expirationDate ?? record.expiresAt ?? record.extractedFields?.expirationDate;
    const deadline = documentDeadline(expiry);
    const approvedCurrent = record.status === 'approved' && Number.isFinite(deadline) && deadline > now;
    const expired = (Number.isFinite(deadline) && deadline <= now) || (heldKinds.includes(kind) && !approvedCurrent);
    const expiryDate = typeof expiry === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(expiry) ? expiry : Number.isFinite(deadline) ? georgiaDate(deadline - 1) : null;
    const daysLeft = expiryDate ? Math.round((Date.parse(expiryDate) - Date.parse(today)) / 86400000) : null;
    const needsReview = !Number.isFinite(deadline) || !['approved', 'expired'].includes(record.status);
    const reminderStage = expired ? 'expired' : daysLeft != null && daysLeft <= 30 && daysLeft >= 0 ? daysLeft <= 1 ? '1_day' : daysLeft <= 7 ? '7_days' : '30_days' : null;
    return { kind, label: DOCUMENT_LABELS[kind], expirationDate: expiryDate, deadline: Number.isFinite(deadline) ? deadline : null, daysLeft, expired, verifiedCurrent: approvedCurrent, needsReview, reminderStage, status: record.status ?? 'missing' };
  });
  const required = config.backgroundChecksRequired === true;
  const requirementVersion = String(config.backgroundCheckRequirementVersion ?? 'open-pilot-v1');
  const report = driver.backgroundScreening ?? {};
  const passed = report.status === 'passed' && Boolean(report.reportReference) && Boolean(report.reviewedBy)
    && Number.isFinite(timestamp(report.completedAt)) && timestamp(report.completedAt) <= now
    && timestamp(report.completedAt) + 366 * 86400000 > now && timestamp(report.validUntil) > now
    && report.requirementVersion === requirementVersion;
  const verificationRequired = config.requireVerifiedDocumentExpirations === true || config.backgroundChecksRequired === true;
  const unverifiedKinds = verificationRequired ? documents.filter(doc => doc.kind !== "vehicleInspection" && !doc.verifiedCurrent).map(doc => doc.kind) : [];
  const expiredKinds = documents.filter(doc => doc.expired).map(doc => doc.kind);
  return {
    documents, documentHold: expiredKinds.length > 0 || unverifiedKinds.length > 0, expiredKinds, unverifiedKinds, verificationRequired,
    expiringKinds: documents.filter(doc => !doc.expired && doc.reminderStage).map(doc => doc.kind),
    needsReviewKinds: documents.filter(doc => doc.needsReview).map(doc => doc.kind),
    backgroundChecksRequired: required, backgroundRequirementVersion: requirementVersion,
    backgroundPassed: passed, backgroundHold: required && !passed,
    drivingAllowed: expiredKinds.length === 0 && unverifiedKinds.length === 0 && (!required || passed)
  };
}
/** @param {Record<string, any>} fields */
function nestedFields(fields) {
  const result = {};
  for (const [path, value] of Object.entries(fields)) {
    if (value === undefined) continue;
    const keys = path.split(".");
    let target = result;
    for (const key of keys.slice(0, -1)) { target[key] ??= {}; target = target[key]; }
    target[keys[keys.length - 1]] = value;
  }
  return result;
}
module.exports = { nestedFields, DOCUMENT_KINDS, DOCUMENT_LABELS, timestamp, georgiaDate, documentDeadline, currentDocument, evaluateDriverCompliance };
