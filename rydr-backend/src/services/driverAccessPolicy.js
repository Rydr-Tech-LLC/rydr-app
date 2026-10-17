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
 return { allowed: reasons.length === 0, title: reasons.length ? 'A few things before you drive' : 'Ready to drive', message: reasons.length ? 'You’re welcome on your Dashboard. Going online will unlock once the items below are cleared.' : 'Your required account checks are complete.', buttonTitle: 'Got it', reasons };
}
module.exports = { driverAccess };
