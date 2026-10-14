const { test } = require('node:test');
const assert = require('node:assert/strict');
const { imageJobId, validImageQuery, allowsAutomaticImport, acceptsAssessment, allowedImageUrl, matchesVehicle } = require('../lib/services/vehicleImageAcquisition');
const query = { make: 'LAND ROVER', model: 'Range Rover Sport', year: 2024, trim: 'P360 SE', color: 'Black', bodyStyle: 'suv' };
const pass = { vehicleMatches: true, yearSupported: true, trimSupported: true, colorMatches: true, whiteBackground: true, singleVehicle: true, noWatermark: true, confidence: 0.98, reason: 'Source and image match' };
test('equivalent queries deduplicate while year, trim, and color are distinct', () => {
  assert.equal(imageJobId(query), imageJobId({ ...query, make: ' land rover ', model: 'range rover sport', color: 'black' }));
  for (const change of [{ year: 2023 }, { trim: 'Autobiography' }, { color: 'White' }]) assert.notEqual(imageJobId(query), imageJobId({ ...query, ...change }));
});
test('malformed and unsupported queries do not create jobs', () => {
  assert.equal(validImageQuery(query), true);
  for (const change of [{ year: NaN }, { year: 1900 }, { make: '' }, { model: undefined }, { color: 'Purple' }, { trim: {} }]) assert.equal(validImageQuery({ ...query, ...change }), false);
});
test('only attribution-free licenses can publish without changing the app', () => {
  for (const license of ['CC0', 'CC0 1.0', 'Public domain']) assert.equal(allowsAutomaticImport({ LicenseShortName: { value: license } }), true);
  for (const license of ['CC BY 4.0', 'CC BY-SA 4.0', '', 'Unknown']) assert.equal(allowsAutomaticImport({ LicenseShortName: { value: license } }), false);
  assert.equal(allowsAutomaticImport({ LicenseShortName: { value: 'CC0' }, AttributionRequired: { value: 'true' } }), false);
  assert.equal(allowsAutomaticImport({ LicenseShortName: { value: 'Public domain' }, Restrictions: { value: 'Restricted' } }), false);
});
test('every match check must pass; model confidence alone never approves', () => {
  assert.equal(acceptsAssessment(pass), true);
  for (const key of ['vehicleMatches', 'yearSupported', 'trimSupported', 'colorMatches', 'whiteBackground', 'singleVehicle', 'noWatermark']) assert.equal(acceptsAssessment({ ...pass, [key]: false }), false);
  for (const confidence of [0.94, NaN, 1.5]) assert.equal(acceptsAssessment({ ...pass, confidence }), false);
  assert.equal(acceptsAssessment({ ...pass, vehicleMatches: 'true' }), false);
});
test('image download host prevents arbitrary URLs and redirects', () => {
  assert.equal(allowedImageUrl('https://upload.wikimedia.org/wikipedia/commons/car.jpg'), true);
  assert.equal(allowedImageUrl('https://thumb.wikimedia.org/wikipedia/commons/thumb/car.jpg'), true);
  assert.equal(allowedImageUrl('https://thumb.wikimedia.org.evil.test/car.jpg'), false);
  for (const url of ['http://upload.wikimedia.org/car.jpg', 'https://upload.wikimedia.org.evil.test/car.jpg', 'https://127.0.0.1/car.jpg', 'https://upload.wikimedia.org:8443/car.jpg', 'https://user:pass@upload.wikimedia.org/car.jpg', 'invalid']) assert.equal(allowedImageUrl(url), false);
});
test('late results cannot update a driver who switched vehicles', () => {
  assert.equal(matchesVehicle({ ...query }, query), true);
  for (const change of [{ color: 'White' }, { year: 2023 }, { trim: null }, { model: 'Defender' }]) assert.equal(matchesVehicle({ ...query, ...change }, query), false);
  assert.equal(matchesVehicle(null, query), false);
});
