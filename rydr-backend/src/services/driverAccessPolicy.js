const { evaluateDriverCompliance } = require('../../firebase/functions/src/services/driverCompliancePolicy');
function driverAccess(driver = {}, policy = {}) {
 const reasons = [], add = (code, title, message) => reasons.push({ code, title, message });
 const status = String(driver.driverApprovalStatus ?? driver.approvalStatus ?? 'pending').toLowerCase();
 const account = String(driver.accountStatus || '').toLowerCase();
 if (driver.safetyHold === true || ['suspended','paused','removed','deletion_requested'].includes(account) || ['suspended','paused','pending','under_review'].includes(String(driver.safetyReviewStatus || '').toLowerCase()))
  add('safety_review','Account access paused','Your account is paused while Rydr reviews a safety or account concern. You can use your Dashboard, but ride requests are unavailable until the review is resolved.');
 if (driver.driverSignupCompleted !== true) add('onboarding','Finish your setup','Complete the remaining onboarding steps before going online.');
 if (driver.identityVerified === false || ['processing','requires_input','canceled','failed','not_started'].includes(driver.identityStatus))
  add('identity','Identity verification',driver.identityStatus === 'processing' ? 'Stripe is reviewing your identity. We will update your account when the review is complete.' : 'Your identity verification needs attention. Finish or update your verification before driving.');
 if (driver.stripePayoutsEnabled === false || driver.payoutsStepCompleted === false)
  add('payout_setup','Payout setup','Finish payout setup and any required account verification before accepting rides. You can manage your payout details from your Dashboard.');
 const compliance = evaluateDriverCompliance(driver, policy);
 if (driver.documentComplianceHold === true || compliance.documentHold)
  add('documents','Document review',compliance.expiredKinds.length ? 'One or more required documents have expired. Upload current documents for approval before driving.' : 'Your required documents are awaiting review or need an update. Driving unlocks after all required documents are approved.');
 if (driver.backgroundCheckHold === true || compliance.backgroundHold)
  add('background_check','Background screening','Complete the required background screening and wait for approval before driving. Your Dashboard will remain available.');
 if (!((status === 'approved' || driver.isApproved === true) && !['rejected','needs_attention'].includes(status)))
  add('account_approval','Rydr account review',status === 'rejected' || status === 'needs_attention' ? 'Your application needs attention from Rydr. Contact support to review the next steps.' : 'Rydr is reviewing your application. We will notify you when your account is approved to drive.');
 const definitions = [
  ['identity', 'Identity verification', 'No current identity restriction.', 'Cleared'],
  ['documents', 'Document review', 'No current document restriction.', 'Cleared'],
  ['background_check', 'Background screening', compliance.backgroundChecksRequired ? 'Your required screening is current.' : 'Screening is not required in the current beta phase.', compliance.backgroundChecksRequired ? 'Cleared' : 'Not required'],
  ['safety_review', 'Safety review', 'There is no active safety hold on your account.', 'No hold'],
  ['payout_setup', 'Payout setup', 'No current payout setup restriction.', 'Ready'],
  ['account_approval', 'Rydr account review', 'Your account is approved to drive.', 'Approved']
 ];
 if (reasons.some(reason => reason.code === 'onboarding')) definitions.unshift(['onboarding','Driver setup','','Needs attention']);
 const checks = definitions.map(([code, title, message, statusLabel]) => {
  const reason = reasons.find(item => item.code === code);
  return {code, title, message: reason?.message ?? message, blocking: Boolean(reason), status: reason ? 'blocking' : code === 'background_check' && !compliance.backgroundChecksRequired ? 'not_required' : 'cleared', statusLabel: reason ? code === 'identity' && driver.identityStatus === 'processing' ? 'In review' : code === 'safety_review' ? 'Paused' : 'Needs attention' : statusLabel};
 });
 return { allowed: reasons.length === 0, title: reasons.length ? 'Your driving checklist' : 'Ready to drive', message: reasons.length ? `${reasons.length} ${reasons.length === 1 ? 'item needs' : 'items need'} attention before you can go online. Highlighted items are the only checks blocking access.` : 'Your required account checks are complete.', buttonTitle: 'Got it', reasons, checks };
}
module.exports = { driverAccess };
