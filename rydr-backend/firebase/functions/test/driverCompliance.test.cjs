const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');
const { Timestamp } = require('firebase-admin/firestore');
const rows = new Map();
const pushes = [];
let failNextPush = false;
function merge(target, value) { for (const [key, item] of Object.entries(value)) { if (item && typeof item === 'object' && !Array.isArray(item) && !(item instanceof Timestamp)) { target[key] ??= {}; merge(target[key], item); } else target[key] = item; } return target; }
function ref(key) {
  return { id: key.split('/').at(-1), path: key, collection: name => collection(`${key}/${name}`),
    get: async () => ({ exists: rows.has(key), data: () => rows.has(key) ? JSON.parse(JSON.stringify(rows.get(key))) : undefined, id: key.split('/').at(-1) }),
    set: async (data, options) => { rows.set(key, options?.merge ? merge(rows.get(key) ?? {}, data) : data); },
    create: async data => { if (rows.has(key)) throw Object.assign(new Error('exists'), { code: 6 }); rows.set(key, data); },
    delete: async () => rows.delete(key)
  };
}
function collection(prefix) {
  let filters = [];
  const query = { doc: id => ref(`${prefix}/${id}`), where: (field, op, value) => { filters.push([field, op, value]); return query; },
    get: async () => { const docs = [...rows.entries()].filter(([key, data]) => key.startsWith(`${prefix}/`) && !key.slice(prefix.length + 1).includes('/') && filters.every(([field, op, value]) => op === 'in' ? value.includes(data[field]) : data[field] === value)).map(([key, data]) => ({ id: key.split('/').at(-1), ref: ref(key), data: () => data })); return { docs, empty: docs.length === 0 }; },
    add: async data => { const doc = ref(`${prefix}/auto_${rows.size}`); await doc.create(data); return doc; }
  }; return query;
}
const db = { collection, runTransaction: async fn => { const writes = []; const tx = { get: doc => doc.get(), update: (doc, data) => writes.push(() => doc.set(data, { merge: true })), set: (doc, data, options) => writes.push(() => doc.set(data, options)) }; const result = await fn(tx); for (const write of writes) await write(); return result; }, batch: () => ({ delete: doc => doc.delete(), commit: async () => {} }) };
const fakeAdmin = { db, Timestamp, FieldValue: { serverTimestamp: () => 'server-time' }, messaging: { sendEachForMulticast: async message => { if (failNextPush) { failNextPush = false; throw new Error('temporary delivery error'); } pushes.push(message); return { successCount: message.tokens.length, failureCount: 0, responses: message.tokens.map(() => ({ success: true })) }; } } };
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '../admin' && parent?.filename.includes(`${path.sep}lib${path.sep}services${path.sep}`)) return fakeAdmin;
  return originalLoad.apply(this, arguments);
};
const { reconcileDriverCompliance } = require('../lib/services/driverComplianceService');
const { sendPushToUser } = require('../lib/services/notificationSender');
Module._load = originalLoad;
const now = Date.parse('2026-10-14T16:00:00Z');
function seed(expiry, extra = {}) {
  rows.clear(); pushes.length = 0;
  rows.set('drivers/fixture', { driverApprovalStatus: 'approved', isApproved: true, isOnline: true, documents: Object.fromEntries(['driverLicense', 'insurance', 'registration'].map(kind => [kind, { status: 'approved', expirationDate: expiry }])), ...extra });
  rows.set('drivers/fixture/notificationTokens/device', { enabled: true, fcmToken: 'test-token' });
}
test('same reminder persists one inbox item per document and attempts one push per document', async () => {
  seed('2026-11-13');
  await reconcileDriverCompliance('fixture', {}, now);
  await reconcileDriverCompliance('fixture', {}, now);
  assert.equal([...rows.keys()].filter(key => key.includes('/notifications/')).length, 3);
  assert.equal(pushes.length, 3);
  assert.equal(pushes[0].data.target, 'documents');
  assert.equal(pushes[0].data.type, 'driverDocumentReminder');
  assert.equal(pushes[0].notification.title.includes('expires soon'), true);
  assert.equal(rows.get('drivers/fixture').documentComplianceHold, false);
});
test('expired documents pause driving; verified replacements restore only the document hold', async () => {
  seed('2026-10-13');
  await reconcileDriverCompliance('fixture', {}, now);
  assert.equal(rows.get('drivers/fixture').canGoOnline, false);
  assert.equal(rows.get('driver_status/fixture').isOnline, false);
  assert.equal(rows.get('drivers/fixture').driverApprovalStatus, 'approved');
  const driver = rows.get('drivers/fixture');
  for (const record of Object.values(driver.documents)) record.expirationDate = '2027-02-01';
  await reconcileDriverCompliance('fixture', {}, now);
  assert.equal(driver.documentComplianceHold, false);
  assert.equal(driver.canGoOnline, true);
  assert.equal(driver.isOnline, false);
  assert.equal(pushes.some(message => message.notification.title === 'Document checks cleared'), true);
  driver.safetyHold = true; driver.documentComplianceHold = true;
  await reconcileDriverCompliance('fixture', {}, now);
  assert.equal(driver.canGoOnline, false);
});
test('open-pilot policy holds a beta-approved account and requires a verified current report', async () => {
  seed('2027-02-01', { betaBackgroundCheckBypassEnabled: true, backgroundCheckAcknowledged: true });
  const policy = { backgroundChecksRequired: true };
  await reconcileDriverCompliance('fixture', policy, now);
  assert.equal(rows.get('drivers/fixture').backgroundCheckHold, true);
  assert.equal(rows.get('drivers/fixture').canGoOnline, false);
  rows.get('drivers/fixture').backgroundScreening = { status: 'passed', reviewedBy: 'admin', reportReference: 'provider/report', completedAt: '2026-10-01T12:00:00Z', validUntil: '2027-10-01T12:00:00Z', requirementVersion: 'open-pilot-v1' };
  await reconcileDriverCompliance('fixture', policy, now);
  assert.equal(rows.get('drivers/fixture').backgroundCheckHold, false);
  assert.equal(rows.get('drivers/fixture').canGoOnline, true);
});
test('transient push failure retries delivery without duplicating the inbox', async () => {
  seed('2027-02-01'); failNextPush = true;
  const args = { audience: 'driver', uid: 'fixture', notificationId: 'retry-test', title: 'Document reminder', body: 'Renew your document', route: { type: 'driverDocumentReminder', target: 'documents' } };
  await sendPushToUser(args);
  assert.equal(rows.get('drivers/fixture/notifications/retry-test').pushStatus, 'retry_pending');
  await sendPushToUser(args); await sendPushToUser(args);
  assert.equal(pushes.length, 1);
  assert.equal(rows.get('drivers/fixture/notifications/retry-test').pushStatus, 'sent');
  assert.equal([...rows.keys()].filter(key => key.endsWith('/retry-test')).length, 1);
});
test('a verified renewal cancels an undelivered expired-document reminder', async () => {
  seed('2026-10-13'); rows.delete('drivers/fixture/notificationTokens/device');
  await reconcileDriverCompliance('fixture', {}, now);
  const queued = [...rows.keys()].filter(key => key.includes('/notifications/document_'));
  assert.equal(queued.length, 3);
  assert.equal(rows.get(queued[0]).pushStatus, 'awaiting_device');
  for (const document of Object.values(rows.get('drivers/fixture').documents)) document.expirationDate = '2027-02-01';
  await reconcileDriverCompliance('fixture', {}, now);
  for (const key of queued) assert.equal(rows.get(key).pushStatus, 'superseded');
});

test('a new pilot screening hold cancels queued access-restored pushes', async () => {
  seed('2026-10-13'); rows.delete('drivers/fixture/notificationTokens/device');
  await reconcileDriverCompliance('fixture', {}, now);
  for (const document of Object.values(rows.get('drivers/fixture').documents)) document.expirationDate = '2027-02-01';
  await reconcileDriverCompliance('fixture', {}, now);
  const restored = [...rows.keys()].find(key => key.includes('/notifications/compliance_restored_'));
  assert.equal(rows.get(restored).pushStatus, 'awaiting_device');
  await reconcileDriverCompliance('fixture', { backgroundChecksRequired: true }, now);
  assert.equal(rows.get(restored).pushStatus, 'superseded');
  assert.equal(rows.get('drivers/fixture').backgroundCheckHold, true);
});

test('strict Live Beta document review allows completed onboarding but blocks driving until all required proof is approved', async () => {
  seed('2027-02-01', { driverSignupCompleted: true, driverOnboardingStatus: 'completed' });
  const driver = rows.get('drivers/fixture');
  driver.documents.insurance.status = 'needs_review';
  await reconcileDriverCompliance('fixture', { requireVerifiedDocumentExpirations: true }, now);
  assert.equal(driver.driverSignupCompleted, true);
  assert.equal(driver.driverOnboardingStatus, 'completed');
  assert.equal(driver.documentComplianceHold, true);
  assert.equal(driver.canGoOnline, false);
  assert.deepEqual(driver.documentComplianceVerificationKinds, ['insurance']);
  driver.documents.insurance.status = 'approved';
  await reconcileDriverCompliance('fixture', { requireVerifiedDocumentExpirations: true }, now);
  assert.equal(driver.documentComplianceHold, false);
  assert.equal(driver.canGoOnline, true);
  assert.equal(driver.isOnline, false);
});
test('manual decline sends one reason-specific inbox and push notification, then suppresses duplicates',async()=>{
 seed('2027-02-01');const driver=rows.get('drivers/fixture');
 Object.assign(driver.documents.insurance,{status:'rejected',reviewReason:'The photo is blurry. Upload a clear, focused photo.',manualReviewId:'decision-1',storagePath:'driverDocuments/fixture/insurance/new.jpg'});
 await reconcileDriverCompliance('fixture',{},now);
 assert.equal(driver.documentComplianceHold,true);assert.equal(driver.canGoOnline,false);
 const declined=[...rows.entries()].filter(([key])=>key.includes('/notifications/document_declined_'));
 assert.equal(declined.length,1);assert.match(declined[0][1].body,/blurry/);assert.equal(declined[0][1].target,'documents');assert.equal(pushes.length,1);
 await reconcileDriverCompliance('fixture',{},now);assert.equal(pushes.length,1);
 Object.assign(driver.documents.insurance,{status:'pending',reviewReason:'Replacement uploaded'});
 await reconcileDriverCompliance('fixture',{requireVerifiedDocumentExpirations:true},now);assert.equal(driver.documentComplianceHold,true);
 driver.documents.insurance.status='approved';await reconcileDriverCompliance('fixture',{requireVerifiedDocumentExpirations:true},now);assert.equal(driver.documentComplianceHold,false);
});
test('declined replacement notifies but preserves still-current approved proof',async()=>{
 seed('2027-02-01');const driver=rows.get('drivers/fixture');
 Object.assign(driver.documents.insurance,{status:'rejected',reviewReason:'Incorrect document.',manualReviewId:'decision-2',approvedRecord:{status:'approved',expirationDate:'2027-02-01'}});
 await reconcileDriverCompliance('fixture',{requireVerifiedDocumentExpirations:true},now);
 assert.equal(driver.documentComplianceHold,false);assert.equal(driver.canGoOnline,true);
 assert.equal([...rows.keys()].some(key=>key.includes('/notifications/document_declined_')),true);
});
