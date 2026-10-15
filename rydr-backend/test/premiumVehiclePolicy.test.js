const { bindPrestineLibrary } = require('../firebase/functions/src/services/prestineLibraryPolicy');
const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluatePremiumVehicle, premiumRideAllowed, vehicleKey, DOCUMENTS } = require('../firebase/functions/src/services/premiumVehiclePolicy');
const now = Date.parse('2026-10-14T12:00:00Z');
function driver(year = 2023, color = 'Black', bodyType = 'suv') {
  const vehicle = { vin: '1GYS4DKL0PR123456', year, make: 'Cadillac', model: 'Escalade', color, plate: 'LM1234' };
  vehicle.libraryEligibility = bindPrestineLibrary(vehicle, { vehicleId: 'test-luxury', make: vehicle.make, model: vehicle.model, yearStart: year, yearEnd: year, bodyStyle: bodyType, eligibleRideTypes: ['Rydr Prestine'], specifications: { verified: true, luxuryClassification: 'luxury' } }, Date.parse('2026-01-01T12:00:00Z'));
  const document = { status: 'verified', verifiedBy: 'admin', verifiedAt: '2026-01-01T12:00:00Z', completedAt: '2026-01-01T12:00:00Z', expiresAt: '2030-12-31T23:59:59-05:00', reference: 'private/document' };
  return { vehicle, license: { state: "GA" }, rating: 4.99, premiumReview: {
    vehicleKey: vehicleKey(vehicle), reviewedBy: 'admin', bodyType, seatCapacity: bodyType === 'suv' ? 7 : 5, operatingState: 'GA', luxuryVehicleApproved: true,
    conditionApproved: true, conditionReview: { ...document }, prestineApprovedAt: '2026-01-01T12:00:00Z',
    blackLeatherInteriorApproved: true, insuranceCoversRydr: true, carrierIdentityMatched: true, registrationPlate: vehicle.plate, reviewedColor: vehicle.color,
    documents: Object.fromEntries(DOCUMENTS.map(spec => [spec.key, { ...document, combinedLimit: 350000 }]))
  }};
}
test('Prestine 2018 cutoff advances and same approved vehicle gets exactly two additional years', () => {
  const d = driver(2018, 'White', 'sedan');
  assert.equal(evaluatePremiumVehicle(d, now).prestine.eligible, true);
  d.premiumReview.conditionReview.verifiedAt = '2027-01-01T05:00:00Z';
  assert.equal(evaluatePremiumVehicle(d, Date.parse('2027-01-01T06:00:00Z')).prestine.grandfathered, true);
  d.premiumReview.conditionReview.verifiedAt = '2028-12-01T12:00:00Z';
  assert.equal(evaluatePremiumVehicle(d, Date.parse('2028-12-31T22:00:00Z')).prestine.eligible, true);
  assert.equal(evaluatePremiumVehicle(d, Date.parse('2029-01-01T05:00:00Z')).prestine.eligible, false);
  d.vehicle.libraryEligibility.firstQualifiedAt = '2027-01-02T12:00:00Z';
  assert.equal(evaluatePremiumVehicle(d, Date.parse('2027-02-01T12:00:00Z')).prestine.eligible, false);
});
test('no automatic premium qualification from brand or stored tier labels', () => {
  assert.equal(premiumRideAllowed({ vehicle: driver().vehicle, eligibleRideTypes: ['Rydr Executive'] }, 'Rydr Executive SUV', now), false);
  const unverifiedVehicle = { ...driver().vehicle }; delete unverifiedVehicle.libraryEligibility;
  assert.deepEqual(evaluatePremiumVehicle({ vehicle: unverifiedVehicle }, now).rideTypes, []);
});
test('Executive requires black exterior/interior, commercial verification and current documents', () => {
  assert.equal(evaluatePremiumVehicle(driver(), now).executive.eligible, true);
  assert.equal(evaluatePremiumVehicle(driver(2023, 'White'), now).executive.eligible, false);
  assert.equal(evaluatePremiumVehicle(driver(2020), now).executive.eligible, false);
  for (const spec of DOCUMENTS) {
    const d = driver(); delete d.premiumReview.documents[spec.key];
    assert.equal(evaluatePremiumVehicle(d, now).executive.eligible, false, spec.key);
  }
  const d = driver(); d.premiumReview.documents.commercialInsurance.expiresAt = '2026-10-13';
  assert.equal(evaluatePremiumVehicle(d, now).executive.eligible, false);
});
test('vehicle replacement invalidates approvals and cannot inherit grandfathering', () => {
  const d = driver(); d.vehicle.vin = 'DIFFERENTVIN';
  assert.deepEqual(evaluatePremiumVehicle(d, now).rideTypes, []);
});
test('Sedan/SUV choices never cross-match; generic legacy tier remains compatible', () => {
  const d = driver();
  assert.equal(premiumRideAllowed(d, 'Rydr Executive SUV', now), true);
  assert.equal(premiumRideAllowed(d, 'Rydr Executive Sedan', now), false);
  assert.equal(premiumRideAllowed(d, 'Rydr Executive', now), true);
  assert.equal(premiumRideAllowed(d, 'Rydr Go', now), true);
});
test('public qualification summary expires without waiting for daily maintenance', () => {
  const d = driver(); const publicProfile = { premiumEligibility: evaluatePremiumVehicle(d, now) };
  assert.equal(premiumRideAllowed(publicProfile, 'Rydr Prestine SUV', now), true);
  assert.equal(premiumRideAllowed(publicProfile, 'Rydr Executive SUV', Date.parse('2030-01-01')), false);
});
test('Executive insurance limits, interior, platform coverage and rating cannot be skipped', () => {
  for (const mutate of [d => d.premiumReview.blackLeatherInteriorApproved = false, d => d.premiumReview.insuranceCoversRydr = false, d => d.rating = 4.9, d => d.premiumReview.documents.commercialInsurance.combinedLimit = 100000]) {
    const d = driver(); mutate(d); assert.equal(evaluatePremiumVehicle(d, now).executive.eligible, false);
  }
});
test('unverified or mismatched license and service hold block Executive only', () => {
  const d = driver(); d.license.state = 'FL';
  assert.equal(evaluatePremiumVehicle(d, now).executive.eligible, false);
  assert.equal(evaluatePremiumVehicle(d, now).prestine.eligible, true);
  d.license.state = 'GA'; d.premiumServiceHold = true;
  assert.equal(evaluatePremiumVehicle(d, now).executive.eligible, false);
});
const { requireExecutiveEnabled } = require('../src/services/premiumPlatformService');
test('paused Executive blocks both body variants at the backend even with an eligible vehicle', async () => {
  const db = { collection: () => ({ doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: false }) }) }) }) };
  await assert.rejects(requireExecutiveEnabled(db, 'Rydr Executive SUV'), /not open/);
  await assert.rejects(requireExecutiveEnabled(db, 'Rydr Executive Sedan'), /not open/);
  await requireExecutiveEnabled(db, 'Rydr Prestine SUV');
});
test('annual screening and safety inspection cannot be extended by a far-future expiry date', () => {
  const d = driver();
  d.premiumReview.conditionReview.verifiedAt = '2027-02-01T12:00:00Z';
  assert.equal(evaluatePremiumVehicle(d, Date.parse('2027-02-02T12:00:00Z')).executive.eligible, false);
});
test('a normal repaint preserves Prestine age grace but cannot create verified black Executive status', () => {
  const d = driver(2018, 'Red'); d.vehicle.color = 'Blue';
  assert.equal(evaluatePremiumVehicle(d, now).prestine.eligible, true);
  const black = driver(2023, 'White'); black.vehicle.color = 'Black';
  assert.equal(evaluatePremiumVehicle(black, now).executive.eligible, false);
});
test('Executive cannot be enabled accidentally before funding approval', async () => {
  let config = { enabled: true, betaPaused: false, fundingApproved: false };
  const db = { collection: () => ({ doc: () => ({ get: async () => ({ exists: true, data: () => config }) }) }) };
  await assert.rejects(requireExecutiveEnabled(db, 'Rydr Executive SUV'), /not open/);
  config = { ...config, fundingApproved: true };
  await requireExecutiveEnabled(db, 'Rydr Executive SUV');
});
test('document readiness never exposes Executive to drivers during the funding hold', () => {
  const { availablePremiumRideTypes } = require('../firebase/functions/src/services/premiumVehiclePolicy');
  const result = evaluatePremiumVehicle(driver(), now);
  assert.equal(result.executive.eligible, true);
  assert.deepEqual(availablePremiumRideTypes(result, { enabled: false, fundingApproved: false }), ['Rydr Prestine SUV']);
  assert.deepEqual(availablePremiumRideTypes(result, { enabled: true, fundingApproved: true, betaPaused: false }), ['Rydr Prestine SUV', 'Rydr Executive SUV']);
});

test('five-seat Range Rover SUV qualifies for Prestine SUV without XL capacity', () => {
  const d = driver(2024, 'Silver', 'suv');
  d.vehicle = { ...d.vehicle, vin: 'SAL1P9EU0RA170245', make: 'LAND ROVER', model: 'Range Rover Sport' };
  d.premiumReview.vehicleKey = vehicleKey(d.vehicle);
  d.premiumReview.seatCapacity = 5;
  d.vehicle.libraryEligibility = bindPrestineLibrary(d.vehicle, { vehicleId: 'range-rover', make: d.vehicle.make, model: d.vehicle.model, yearStart: 2024, yearEnd: 2024, bodyStyle: 'suv', eligibleRideTypes: ['Rydr Go', 'Rydr Prestine'], specifications: { verified: true, luxuryClassification: 'luxury' } }, now);
  const result = evaluatePremiumVehicle(d, now);
  assert.equal(result.prestine.eligible, true);
  assert.ok(result.rideTypes.includes('Rydr Prestine SUV'));
  assert.equal(result.rideTypes.includes('Rydr Prestine Sedan'), false);
  assert.equal(result.rideTypes.includes('Rydr XL'), false);
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine SUV', now), true);
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine Sedan', now), false);
});

test('Prestine needs no premium review, condition expiry, professional documents or trip rating', () => {
  const d = driver(); delete d.premiumReview; d.rating = 0;
  assert.equal(evaluatePremiumVehicle(d, now).prestine.eligible, true);
  assert.equal(evaluatePremiumVehicle(d, now).executive.eligible, false);
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine SUV', now), true);
  const nextYear = Date.parse('2027-10-14T12:00:00Z');
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine SUV', nextYear), true);
});
test('library revocation, wrong model/year/trim and unsupported body styles remove Prestine', () => {
  const d = driver();
  const entry = { vehicleId: 'test', make: d.vehicle.make, model: d.vehicle.model, yearStart: 2023, yearEnd: 2023, bodyStyle: 'suv', eligibleRideTypes: ['Rydr Prestine'], specifications: { verified: true, luxuryClassification: 'luxury' } };
  for (const change of [{ eligibleRideTypes: ['Rydr Go'] }, { model: 'Other model' }, { yearStart: 2024 }, { trim: 'Other trim' }, { bodyStyle: 'coupe' }]) {
    const vehicle = { ...d.vehicle, libraryEligibility: bindPrestineLibrary(d.vehicle, { ...entry, ...change }, now) };
    assert.equal(evaluatePremiumVehicle({ vehicle }, now).prestine.eligible, false);
  }
});
test('a selected non-premium vehicle cannot inherit another garage vehicle qualification', () => {
  const d = driver();
  d.vehicle = { ...d.vehicle, vin: 'SAL1P9EU0RA170245', make: 'Chevrolet', model: 'Equinox' };
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine SUV', now), false);
});
test('Sedan library body classification is independent of old Executive review or seat count', () => {
  const d = driver(2023, 'White', 'sedan'); delete d.premiumReview;
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine Sedan', now), true);
  assert.equal(premiumRideAllowed(d, 'Rydr Prestine SUV', now), false);
});
