const { admin, getFirestore } = require('../config/firebase');
const { onboardingState } = require('../../firebase/functions/src/services/onboardingProgress');
function fail(message, statusCode = 400) { return Object.assign(new Error(message), { statusCode }); }
function resumeProfile(profile, token) {
  const address = profile.address || {}, vehicle = profile.vehicle || {}, license = profile.license || {};
  let dob;
  try { dob = profile.dob?.toDate?.().toISOString() || (profile.dob ? new Date(profile.dob).toISOString() : undefined); } catch {}
  return {
    firstName: profile.firstName || '', lastName: profile.lastName || '', preferredName: profile.preferredName || '', email: profile.email || token.email || '', phoneNumber: token.phone_number || profile.phoneE164 || profile.phoneNumber || '', dob: dob || null,
    driverSex: ["male", "female"].includes(profile.driverSex) ? profile.driverSex : "undisclosed",
    address: { street: address.street || address.line1 || '', line2: address.line2 || '', city: address.city || '', state: address.state || '', zip: address.zip || address.postal_code || '' },
    license: { number: license.number || '', state: license.state || '' },
    vehicle: { vin: vehicle.vin || '', make: vehicle.make || '', model: vehicle.model || '', year: String(vehicle.year || ''), trim: vehicle.trim || null, bodyStyle: vehicle.bodyStyle || null, fuelType: vehicle.fuelType || 'gas', color: vehicle.color || '', plate: vehicle.plate || '' },
    betaWaiverAccepted: profile.betaWaiverAccepted === true, backgroundCheckAcknowledged: profile.backgroundCheckAcknowledged === true
  };
}
async function getOnboardingStatus({ uid, role, token, db = getFirestore() }) {
  if (!['rider', 'driver'].includes(role)) throw fail('role must be rider or driver');
  const profile = (await db.collection(role === 'driver' ? 'drivers' : 'riders').doc(uid).get()).data() || {};
  return { ...onboardingState(role, profile, token), profile: resumeProfile(profile, token) };
}
async function recordOnboardingCheckpoint({ uid, role, step, db = getFirestore() }) {
  if (role !== 'rider' || step !== 'paymentMethod') throw fail('Unsupported onboarding checkpoint');
  const ref = db.collection('riders').doc(uid);
  await ref.set({ riderPaymentStepCompleted: true, updatedAt: admin.firestore.Timestamp.now() }, { merge: true });
  return { ok: true };
}
module.exports = { onboardingState, resumeProfile, getOnboardingStatus, recordOnboardingCheckpoint };
