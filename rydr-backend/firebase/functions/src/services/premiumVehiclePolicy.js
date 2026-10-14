// Shared by Firebase, the dispatch backend, and Mission Control. Premium
// qualification is vehicle-bound, admin-owned, and reevaluated at dispatch.
const { createHash } = require('node:crypto');
const DOCUMENTS = [
  { key: 'driverLicense', label: 'Current Georgia driver license', expires: true },
  { key: 'backgroundScreening', label: 'Annual criminal, driving-history and sex-offender screening', expires: true, maxDays: 366 },
  { key: 'carrierAuthority', label: 'Georgia Class B Limousine Carrier Certificate', expires: false },
  { key: 'commercialInsurance', label: 'Commercial auto liability insurance', expires: true },
  { key: 'limoRegistration', label: 'Georgia Limousine registration and LM plate', expires: true },
  { key: 'forHireQualification', label: 'DDS For-Hire endorsement OR qualifying background-check certification', expires: true },
  { key: 'safetyInspection', label: 'Annual Georgia DPS vehicle safety inspection', expires: true, maxDays: 366 },
  { key: 'carrierRegistration', label: 'Current GIMC registration (or applicable UCR)', expires: true },
  { key: 'carrierMarkings', label: 'Required carrier vehicle identification markings', expires: false },
  { key: 'professionalService', label: 'Professional service training and conduct review', expires: false }
];
/** @param {any} value */
function text(value) { return String(value ?? '').trim().toLowerCase(); }
/** @param {any} value */
function millis(value) {
  if (!value) return NaN;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value.seconds != null) return Number(value.seconds) * 1000;
  return new Date(value).getTime();
}
/** @param {any} vehicle */
function vehicleKey(vehicle) {
  return createHash('sha256').update(['vin', 'year', 'make', 'model'].map(key => text(vehicle?.[key])).join('|')).digest('hex');
}
/** @param {any} document @param {number} now @param {boolean} expires @param {number} [maxDays] */
function verified(document, now, expires, maxDays = Infinity) {
  return document?.status === 'verified' && typeof document.reference === 'string' && Boolean(document.reference.trim())
    && Boolean(document.verifiedBy) && Number.isFinite(millis(document.verifiedAt))
    && millis(document.verifiedAt) <= now
    && (!Number.isFinite(maxDays) || (Number.isFinite(millis(document.completedAt)) && millis(document.completedAt) <= now && now < millis(document.completedAt) + maxDays * 86400000))
    && (!expires || millis(document.expiresAt) > now);
}
/** @param {any} driver @param {number} [now] */
function evaluatePremiumVehicle(driver, now = Date.now()) {
  const vehicle = driver?.vehicle ?? {};
  const review = driver?.premiumReview ?? {};
  const year = Number(vehicle.year);
  const currentYear = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric' }).format(new Date(now)));
  const minimumYear = currentYear - 8;
  const bound = review.vehicleKey === vehicleKey(vehicle) && Boolean(review.reviewedBy);
  const bodyType = bound && ['sedan', 'suv'].includes(review.bodyType) ? review.bodyType : null;
  const baseIssues = [];
  if (!/^[A-HJ-NPR-Z0-9]{17}$/i.test(String(vehicle.vin ?? ''))) baseIssues.push('Verified 17-character VIN required');
  if (!bound) baseIssues.push('Vehicle-specific Mission Control review required');
  if (!bodyType) baseIssues.push('Approved Sedan or SUV classification required');
  const seats = Number(review.seatCapacity);
  if (!Number.isInteger(seats) || seats < 5 || seats > 8) baseIssues.push('Verified seating capacity of 5–8 including the driver required');
  if (!bound || review.luxuryVehicleApproved !== true) baseIssues.push('Luxury make/model approval required');
  if (!bound || review.conditionApproved !== true || !verified({ ...review.conditionReview, completedAt: review.conditionReview?.verifiedAt }, now, true, 366)) baseIssues.push('Current vehicle condition review required');
  const prestineIssues = [...baseIssues];
  const approvedAt = millis(review.prestineApprovedAt);
  const approvedYear = Number.isFinite(approvedAt)
    ? Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric' }).format(new Date(approvedAt))) : NaN;
  const grandfathered = bound && Number.isFinite(approvedAt) && approvedAt <= now
    && year >= approvedYear - 8 && currentYear <= year + 10;
  if (!Number.isInteger(year) || year < 1900 || year > currentYear + 1 || (year < minimumYear && !grandfathered)) prestineIssues.push(`Minimum model year ${minimumYear}; existing vehicle grace ends December 31, ${year + 10}`);
  if (!Number.isFinite(approvedAt) || approvedAt > now) prestineIssues.push('Prestine approval required');
  const executiveIssues = [...baseIssues];
  if (bodyType === "suv" && seats < 7) executiveIssues.push("Executive SUV requires seating for six riders plus the driver");
  if (!Number.isInteger(year) || year < currentYear - 5 || year > currentYear + 1) executiveIssues.push(`Executive minimum model year ${currentYear - 5}`);
  if (text(vehicle.color) !== 'black' || text(review.reviewedColor) !== 'black') executiveIssues.push('Verified black exterior required');
  if (!bound || review.blackLeatherInteriorApproved !== true) executiveIssues.push('Black leather or vegan-leather interior required');
  if (!/^lm/i.test(String(vehicle.plate ?? '')) && review.temporaryLimoRegistration !== true) executiveIssues.push('Georgia LM plate or verified temporary limousine registration required');
  if (text(review.registrationPlate) !== text(vehicle.plate)) executiveIssues.push('Registration review must match current vehicle plate');
  if (review.carrierIdentityMatched !== true) executiveIssues.push('Carrier, insured name and vehicle identity match must be verified');
  if (text(driver?.license?.state) !== 'ga') executiveIssues.push('Georgia-issued driver license required');
  if (review.operatingState !== 'GA') executiveIssues.push('Georgia commercial operating review required');
  for (const doc of DOCUMENTS) {
    if (!bound || !verified(review.documents?.[doc.key], now, doc.expires, doc.maxDays ?? Infinity)) executiveIssues.push(doc.label);
  }
  const insurance = review.documents?.commercialInsurance ?? {};
  if (!(Number(insurance.combinedLimit) >= 350000 || (Number(insurance.bodilyPerPerson) >= 100000 && Number(insurance.bodilyPerAccident) >= 300000 && Number(insurance.propertyDamage) >= 50000))) executiveIssues.push('Commercial liability limits must meet the Georgia/Atlanta minimum');
  if (!bound || review.insuranceCoversRydr !== true) executiveIssues.push('Insurance must cover Executive operations on Rydr');
  if (driver?.premiumServiceHold === true) executiveIssues.push('Professional service review hold');
  if (!Number.isFinite(Number(driver?.rating ?? 5)) || Number(driver?.rating ?? 5) < 4.95) executiveIssues.push('Executive minimum driver rating is 4.95');
  const suffix = bodyType === 'suv' ? 'SUV' : 'Sedan';
  return {
    policyVersion: 'ga-premium-2026-v1', bodyType, minimumYear,
    prestine: { validUntil: Math.min((millis(review.conditionReview?.verifiedAt) || 0) + 366 * 86400000, Number.isFinite(millis(review.conditionReview?.expiresAt)) ? millis(review.conditionReview?.expiresAt) : 0, Number.isInteger(year) ? Date.parse(`${year + 11}-01-01T00:00:00-05:00`) : 0), eligible: prestineIssues.length === 0, issues: prestineIssues, grandfathered: year < minimumYear && grandfathered, lastEligibleYear: year + 10 },
    executive: { validUntil: Math.min((millis(review.conditionReview?.verifiedAt) || 0) + 366 * 86400000, (millis(review.documents?.safetyInspection?.completedAt) || 0) + 366 * 86400000, (millis(review.documents?.backgroundScreening?.completedAt) || 0) + 366 * 86400000, Number.isFinite(millis(review.conditionReview?.expiresAt)) ? millis(review.conditionReview?.expiresAt) : 0, Number.isInteger(year) ? Date.parse(`${year + 6}-01-01T00:00:00-05:00`) : 0, ...DOCUMENTS.filter(doc => doc.expires).map(doc => (Number.isFinite(millis(review.documents?.[doc.key]?.expiresAt)) ? millis(review.documents?.[doc.key]?.expiresAt) : 0))), eligible: executiveIssues.length === 0, issues: executiveIssues, airportEligible: executiveIssues.length === 0 && verified(review.documents?.airportAuthorization, now, true) },
    rideTypes: [...(prestineIssues.length === 0 ? [`Rydr Prestine ${suffix}`] : []), ...(executiveIssues.length === 0 ? [`Rydr Executive ${suffix}`] : [])]
  };
}
/** @param {any} profile @param {string} rideType @param {number} [now] */
function premiumRideAllowed(profile, rideType, now = Date.now()) {
  const tier = text(rideType);
  if (!tier.includes('prestine') && !tier.includes('pristine') && !tier.includes('executive')) return true;
  const result = profile.vehicle ? evaluatePremiumVehicle(profile, now) : profile.premiumEligibility;
  if (!result) return false;
  if (tier.includes('suv') && result.bodyType !== 'suv') return false;
  if (tier.includes('sedan') && result.bodyType !== 'sedan') return false;
  const qualification = tier.includes('executive') ? result.executive : result.prestine;
  return qualification?.eligible === true && Number(qualification.validUntil) > now;
}
/** @param {any} evaluation @param {any} [config] */
function availablePremiumRideTypes(evaluation, config = {}) {
  const executiveOpen = config.enabled === true && config.fundingApproved === true && config.betaPaused !== true;
  return evaluation.rideTypes.filter(type => !type.includes("Executive") || executiveOpen);
}
module.exports = { availablePremiumRideTypes, DOCUMENTS, vehicleKey, evaluatePremiumVehicle, premiumRideAllowed, verified };
