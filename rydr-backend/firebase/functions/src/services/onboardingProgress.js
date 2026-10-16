const BETA_WAIVER_VERSION = "2026-07-04";
function fail(message) { return Object.assign(new Error(message), { statusCode: 400 }); }
const text = value => typeof value === 'string' && value.trim().length > 0;
function onboardingState(role, profile = {}, token = {}) {
  if (!['rider', 'driver'].includes(role)) throw fail('role must be rider or driver');
  if (profile[role === 'driver' ? 'driverSignupCompleted' : 'riderSignupCompleted'] === true) return { completed: true, nextStep: null, cashHubOnly: false };
  if (role === 'rider' && profile.cashHubRole === 'rider' && profile.hasRydrRiderAccess === false && profile.riderOnboardingStarted !== true) return { completed: true, nextStep: null, cashHubOnly: true };
  let nextStep;
  const address = profile.address || {};
  if (!text(token.phone_number || profile.phoneE164 || profile.phoneNumber)) nextStep = 'phone';
  else if ((profile.betaWaiverAccepted !== true || profile.betaWaiverVersion !== BETA_WAIVER_VERSION)) nextStep = 'betaWaiver';
  else if (!text(profile.firstName) || !text(profile.lastName) || (role === 'driver' && !profile.dob)) nextStep = role === 'driver' ? 'nameDOB' : 'nameEntry';
  else if (!text(token.email) && profile.emailPasswordStepCompleted !== true && profile.socialAuthLinked !== true) nextStep = 'emailPassword';
  else if (!text(address.street || address.line1) || !text(address.city) || !text(address.state) || !text(address.zip || address.postal_code)) nextStep = role === 'driver' ? 'address' : 'addressEntry';
  else if (role === 'rider') nextStep = profile.riderPaymentStepCompleted === true || profile.stripeIdentityVerificationId ? 'termsAndVerification' : 'paymentMethod';
  else if (profile.licenseStepCompleted !== true) nextStep = 'license';
  else if (profile.vehicleStepCompleted !== true) nextStep = 'vehicle';
  else if (!(profile.identityVerified === true && profile.identityVerificationStepCompleted === true) && !(profile.identityStatus === 'processing' && /^vs_[a-zA-Z0-9]+$/.test(profile.stripeIdentityVerificationId || ''))) nextStep = 'identity';
  else if (profile.backgroundCheckStepCompleted !== true) nextStep = 'backgroundCheck';
  else nextStep = 'payouts'; // Also retries server finalization if Connect is already ready.
  return { completed: false, nextStep, cashHubOnly: false };
}
module.exports = { onboardingState, BETA_WAIVER_VERSION };
