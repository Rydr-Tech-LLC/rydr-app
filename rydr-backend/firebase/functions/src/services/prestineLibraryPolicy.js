const { createHash } = require('node:crypto');
const { exactLibraryEntry } = require('./vehicleSpecificationPolicy');
const clean = value => String(value ?? '').trim().toLowerCase();
function selectedVehicleKey(vehicle) {
  return createHash('sha256').update(['vin', 'year', 'make', 'model', 'trim'].map(key => clean(vehicle?.[key])).join('|')).digest('hex');
}
// This snapshot lives inside the backend-owned vehicle record. Client tier
// labels and a previous vehicle's qualification are never accepted as evidence.
function bindPrestineLibrary(vehicle, entry, now = Date.now()) {
  const match = entry && exactLibraryEntry([entry], vehicle);
  const eligible = Boolean(match && Array.isArray(entry.eligibleRideTypes)
    && entry.eligibleRideTypes.some(type => /^rydr prestine(?: suv| sedan)?$/i.test(type))
    && ['suv', 'sedan'].includes(entry.bodyStyle)
    && entry.specifications?.verified === true && entry.specifications?.luxuryClassification === 'luxury');
  const key = selectedVehicleKey(vehicle);
  const previous = vehicle?.libraryEligibility;
  const previousAt = Date.parse(previous?.firstQualifiedAt ?? '');
  const currentYear = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric' }).format(new Date(now)));
  const retainsGrace = previous?.vehicleKey === key && previous?.prestine === true && Number.isFinite(previousAt) && previousAt <= now;
  return { vehicleKey: key, libraryVehicleId: match?.vehicleId ?? null, prestine: eligible,
    bodyType: eligible ? entry.bodyStyle : null,
    firstQualifiedAt: eligible && retainsGrace ? previous.firstQualifiedAt : eligible && Number(vehicle.year) >= currentYear - 8 ? new Date(now).toISOString() : null };
}
function evaluatePrestineLibrary(vehicle, now = Date.now()) {
  const snapshot = vehicle?.libraryEligibility;
  const bound = snapshot?.vehicleKey === selectedVehicleKey(vehicle) && snapshot?.prestine === true;
  const bodyType = bound && ['suv', 'sedan'].includes(snapshot.bodyType) ? snapshot.bodyType : null;
  const currentYear = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric' }).format(new Date(now)));
  const year = Number(vehicle?.year), minimumYear = currentYear - 8;
  const approvedAt = Date.parse(snapshot?.firstQualifiedAt ?? '');
  const approvedYear = Number.isFinite(approvedAt) ? Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric' }).format(new Date(approvedAt))) : NaN;
  const grandfathered = bound && approvedAt <= now && year >= approvedYear - 8 && currentYear <= year + 10;
  const issues = [];
  if (!bound) issues.push('Selected vehicle must match a Prestine-eligible luxury Vehicle Library entry');
  if (!bodyType) issues.push('Vehicle Library must classify the vehicle as SUV or Sedan');
  if (!Number.isInteger(year) || year < 1900 || year > currentYear + 1 || (year < minimumYear && !grandfathered)) issues.push(`Minimum model year ${minimumYear}; existing vehicle grace ends December 31, ${year + 10}`);
  return { bodyType, minimumYear, eligible: issues.length === 0, issues, grandfathered: year < minimumYear && grandfathered,
    lastEligibleYear: year + 10, validUntil: Number.isInteger(year) ? Date.parse(`${year + (grandfathered ? 11 : 9)}-01-01T00:00:00-05:00`) : 0 };
}
module.exports = { bindPrestineLibrary, evaluatePrestineLibrary, selectedVehicleKey };
