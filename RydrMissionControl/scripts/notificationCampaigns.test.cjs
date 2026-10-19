const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
function load(relative, mocks) {
  const filename = path.join(__dirname, '..', relative);
  const js = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const module = { exports: {} };
  new Function('require', 'module', 'exports', js)(name => name in mocks ? mocks[name] : require(name), module, module.exports);
  return module.exports;
}
const records = new Map();
const ref = id => ({ id });
const db = { collection: () => ({ doc: ref }), runTransaction: async fn => fn({
  get: async r => ({ exists: records.has(r.id), ref: r }), create: (r, data) => records.set(r.id, data)
}) };
const policy = load('lib/notificationCampaigns.ts', {
  'server-only': {}, './firebaseAdmin': { getControlDb: () => db },
  'firebase-admin/firestore': { FieldValue: { serverTimestamp: () => 'now' }, Timestamp: { fromDate: d => d } }
});
test('9 AM Eastern beta dates account for the November DST transition', () => {
  const times = policy.betaSchedule.map(row => new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: '2-digit' }).format(new Date(row.at)));
  assert.deepEqual(times, ['9:00 AM', '9:00 AM', '9:00 AM']);
  assert.deepEqual(policy.betaSchedule.map(row => row.at.slice(0, 10)), ['2026-10-27', '2026-10-29', '2026-11-01']);
});
test('beta seed creates six audience-specific announcements and preserves cancellation', async () => {
  await policy.seedBetaSchedule('admin'); assert.equal(records.size, 6);
  const rider = records.get('live-beta-2026-launch-rider'); const driver = records.get('live-beta-2026-launch-driver');
  assert.match(rider.body, /first ride/); assert.match(driver.body, /Go online/);
  rider.status = 'cancelled'; await policy.seedBetaSchedule('admin');
  assert.equal(records.size, 6); assert.equal(records.get('live-beta-2026-launch-rider').status, 'cancelled');
});
test('validation rejects empty, oversized, invalid audience, past and timezone-free requests', () => {
  const valid = { title: 'Beta', body: 'Hello', audience: 'rider', sendAt: '2099-11-01T09:00:00-05:00' };
  assert.equal(policy.validateAnnouncement(valid).sendAt.toISOString(), '2099-11-01T14:00:00.000Z');
  for (const update of [{ title: '' }, { body: 'x'.repeat(501) }, { audience: 'all' }, { sendAt: '2020-01-01T00:00:00Z' }, { sendAt: '2099-11-01T09:00:00' }]) assert.throws(() => policy.validateAnnouncement({ ...valid, ...update }));
});
test('notifications API rejects unauthenticated reads and writes before database access', async () => {
  const api = load('app/api/notifications/route.ts', {
    'next/server': { NextResponse: { json: (body, options) => ({ body, status: options.status }) } },
    'firebase-admin/firestore': {}, '@/lib/session': { getAdminSession: async () => null },
    '@/lib/firebaseAdmin': {}, '@/lib/auditLog': {}, '@/lib/notificationCampaigns': {}, '@/lib/workspace': {}
  });
  assert.equal((await api.GET()).status, 401); assert.equal((await api.POST({})).status, 401);
});

test('test workspace cannot send or manage live app announcements', async () => {
  const api = load('app/api/notifications/route.ts', {
    'next/server': { NextResponse: { json: (body, options) => ({ body, status: options.status }) } },
    'firebase-admin/firestore': {}, '@/lib/session': { getAdminSession: async () => ({uid: 'admin'}) },
    '@/lib/workspace': { currentWorkspace: async () => 'test' },
    '@/lib/firebaseAdmin': { getControlDb: () => { throw Error('Must not access live data'); } },
    '@/lib/auditLog': {}, '@/lib/notificationCampaigns': {}
  });
  assert.equal((await api.GET()).status, 409);
  assert.equal((await api.POST({})).status, 409);
});
