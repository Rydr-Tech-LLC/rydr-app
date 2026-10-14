const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateDriverCompliance, documentDeadline, nestedFields } = require('../firebase/functions/src/services/driverCompliancePolicy');
const { isApprovedDriver } = require('../src/services/driverPresenceService');
const now = Date.parse('2026-10-14T16:00:00Z');
function driver(expiry = '2027-02-01') {
  return { driverApprovalStatus: 'approved', isApproved: true, documents: Object.fromEntries(['driverLicense', 'insurance', 'registration'].map(kind => [kind, { status: 'approved', expirationDate: expiry, storagePath: `driverDocuments/test/${kind}/front.jpg` }])) };
}
test('date-only documents expire after the full Georgia day, including DST boundaries', () => {
  assert.equal(documentDeadline('2026-10-14'), Date.parse('2026-10-15T04:00:00Z'));
  assert.equal(documentDeadline('2026-11-01'), Date.parse('2026-11-02T05:00:00Z'));
  assert.equal(documentDeadline('2027-03-14'), Date.parse('2027-03-15T04:00:00Z'));
  assert.equal(evaluateDriverCompliance(driver('2026-10-14'), {}, now).documentHold, false);
  assert.equal(evaluateDriverCompliance(driver('2026-10-14'), {}, Date.parse('2026-10-15T04:00:00Z')).documentHold, true);
});
test('reminders cover 30, 7, 1 days and expiry without repeated new stages', () => {
  for (const [expiry, stage] of [['2026-11-13', '30_days'], ['2026-10-21', '7_days'], ['2026-10-15', '1_day'], ['2026-10-13', 'expired']]) {
    assert.equal(evaluateDriverCompliance(driver(expiry), {}, now).documents[0].reminderStage, stage);
  }
  assert.equal(evaluateDriverCompliance(driver('2026-11-14'), {}, now).documents[0].reminderStage, null);
});
test('an approved beta account cannot drive with a known expired document', () => {
  const d = driver('2020-01-01');
  assert.equal(isApprovedDriver(d), false);
  assert.equal(evaluateDriverCompliance(d, {}, now).documentHold, true);
});
test('pending or rejected replacements cannot clear an expired-document hold', () => {
  const d = driver(); d.documentComplianceExpiredKinds = ['insurance'];
  for (const status of ['pending', 'needs_review', 'rejected']) {
    d.documents.insurance.status = status;
    assert.equal(evaluateDriverCompliance(d, {}, now).documentHold, true);
  }
  d.documents.insurance.status = 'approved';
  assert.equal(evaluateDriverCompliance(d, {}, now).documentHold, false);
});
test('last approved document stays active while a replacement is pending', () => {
  const d = driver(); d.documents.insurance = { status: 'pending', approvedRecord: { status: 'approved', expirationDate: '2027-02-01' } };
  assert.equal(evaluateDriverCompliance(d, {}, now).documentHold, false);
  assert.equal(evaluateDriverCompliance(d, {}, Date.parse('2027-02-02T05:00:00Z')).documentHold, true);
});
test('renewing one document does not clear another expired document or a safety suspension', () => {
  const d = driver(); d.documents.registration.expirationDate = '2026-10-13';
  assert.deepEqual(evaluateDriverCompliance(d, {}, now).expiredKinds, ['registration']);
  d.documents.registration.expirationDate = '2027-02-01'; d.safetyHold = true;
  assert.equal(isApprovedDriver(d), false);
  d.safetyHold = false; d.accountStatus = 'suspended';
  assert.equal(isApprovedDriver(d), false);
});
test('unknown legacy dates are flagged for review instead of being invented as expired', () => {
  const result = evaluateDriverCompliance({ isApproved: true }, {}, now);
  assert.equal(result.documentHold, false);
  assert.deepEqual(result.needsReviewKinds, ['driverLicense', 'insurance', 'registration']);
  assert.equal(Number.isNaN(documentDeadline('2026-02-30')), true);
});
test('legacy dotted review fields and expiry aliases remain readable', () => {
  const d = { 'documents.insurance.status': 'approved', 'documents.insurance.extractedFields': { expirationDate: '2026-10-13' }, driverLicenseExpiresAt: '2026-10-13' };
  assert.deepEqual(evaluateDriverCompliance(d, {}, now).expiredKinds, ['driverLicense', 'insurance']);
  assert.deepEqual(nestedFields({ 'documents.insurance.status': 'approved', 'documents.insurance.expirationDate': '2027-01-01', updatedAt: 3 }), { documents: { insurance: { status: 'approved', expirationDate: '2027-01-01' } }, updatedAt: 3 });
});
test('open-pilot policy includes every beta-approved driver; acknowledgement and bypass do not qualify', () => {
  const d = driver(); d.betaBackgroundCheckBypassEnabled = true; d.backgroundCheckAcknowledged = true; d.backgroundCheckPassed = true;
  assert.equal(evaluateDriverCompliance(d, { backgroundChecksRequired: false }, now).drivingAllowed, true);
  assert.equal(evaluateDriverCompliance(d, { backgroundChecksRequired: true }, now).backgroundHold, true);
});
test('verified current screening restores eligibility, and old versions or expired reports block it', () => {
  const d = driver(); d.backgroundScreening = { status: 'passed', reportReference: 'private/report', reviewedBy: 'admin', completedAt: '2026-10-01T12:00:00Z', validUntil: '2027-10-01T12:00:00Z', requirementVersion: 'open-pilot-v1' };
  const config = { backgroundChecksRequired: true };
  assert.equal(evaluateDriverCompliance(d, config, now).backgroundHold, false);
  d.backgroundScreening.requirementVersion = 'old-beta';
  assert.equal(evaluateDriverCompliance(d, config, now).backgroundHold, true);
  d.backgroundScreening.requirementVersion = 'open-pilot-v1';
  assert.equal(evaluateDriverCompliance(d, config, Date.parse('2027-10-02T12:00:00Z')).backgroundHold, true);
});
test('open-pilot screening approval does not bypass missing verified document dates', () => {
  const d = { isApproved: true, driverApprovalStatus: 'approved', backgroundScreening: { status: 'passed', reportReference: 'private/report', reviewedBy: 'admin', completedAt: '2026-10-01T12:00:00Z', validUntil: '2027-10-01T12:00:00Z', requirementVersion: 'open-pilot-v1' } };
  const result = evaluateDriverCompliance(d, { backgroundChecksRequired: true }, now);
  assert.equal(result.backgroundPassed, true);
  assert.equal(result.documentHold, true);
  assert.equal(result.drivingAllowed, false);
  assert.deepEqual(result.unverifiedKinds, ['driverLicense', 'insurance', 'registration']);
});
