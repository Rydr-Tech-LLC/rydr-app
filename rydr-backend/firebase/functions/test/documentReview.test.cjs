const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const rows = new Map();
let blockedOCR;
let text = 'INSURANCE POLICY\nPolicy Number: POLICY123456\nInsured: TEST DRIVER\nExpiration: 11/13/2099\nEffective Date: 10/13/2026\nVIN: SAL1P9EU0RA170245';
function merge(a,b) { for (const [k,v] of Object.entries(b)) { if (v && typeof v === 'object' && !Array.isArray(v)) { a[k] ??= {}; merge(a[k],v); } else a[k]=v; } return a; }
function ref(key) {
 return {
  collection: n => ({doc: id => ref(`${key}/${n}/${id}`)}),
  get: async () => ({exists: rows.has(key), data: () => rows.has(key) ? structuredClone(rows.get(key)) : undefined}),
  set: async (data, options) => {
   if (options?.mergeFields) {
    const row = rows.get(key) ?? {};
    for (const field of options.mergeFields) {
     const parts = field.split('.');
     const value = parts.reduce((parent, part) => parent[part], data);
     const last = parts.pop();
     const target = parts.reduce((parent, part) => parent[part] ??= {}, row);
     target[last] = structuredClone(value);
    }
    rows.set(key, row);
   } else {
    rows.set(key, options?.merge ? merge(rows.get(key) ?? {}, data) : data);
   }
  }
 };
}
const db = {
 collection: n => ({doc: id => ref(`${n}/${id}`)}),
 runTransaction: async fn => {
  const writes = [];
  const result = await fn({get: r => r.get(), set: (r, d, o) => writes.push(() => r.set(d, o))});
  for (const write of writes) await write();
  return result;
 },
 batch: () => ({})
};
const load=Module._load;
Module._load=function(request,parent) {
 if(request==='../admin' && parent?.filename.endsWith('documentReviewService.js')) return {db,FieldValue:{serverTimestamp:()=> 'server-time'}};
 return load.apply(this,arguments);
};
const fetchBefore = globalThis.fetch;
globalThis.fetch = async url => {
 if (String(url).includes('metadata.google')) return {ok:true,json:async()=>({access_token:'fixture-only'})};
 if (blockedOCR) {
  const wait = blockedOCR;
  blockedOCR = null;
  await wait;
 }
 return {ok:true,json:async()=>({responses:[{fullTextAnnotation:{text}}]})};
};
test.after(() => { globalThis.fetch = fetchBefore; });
const {reviewUploadedDocument}=require('../lib/services/documentReviewService');
Module._load=load;
const {evaluateDriverCompliance}=require('../src/services/driverCompliancePolicy');
function seed() { rows.clear(); rows.set('drivers/test',{firstName:'Test',lastName:'Driver',vehicle:{vin:'SAL1P9EU0RA170245'},documents:{insurance:{status:'approved',expirationDate:'2026-10-13',storagePath:'driverDocuments/test/insurance/old.jpg',extractedFields:{licenseNumber:'STALE'},generation:'100'},driverLicense:{status:'approved',expirationDate:'2027-01-01'},registration:{status:'approved',expirationDate:'2027-01-01'}}}); }
const upload=(generation,file='new.jpg')=>reviewUploadedDocument({bucket:'fixture',contentType:'image/jpeg',generation,storagePath:`driverDocuments/test/insurance/${file}`});
test('pending renewal keeps approved proof; final OCR writes nested fields and restores eligibility',async()=>{
 seed(); let release; blockedOCR=new Promise(resolve=>{release=resolve;});
 const pending=upload('200');
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(rows.get('drivers/test').documents.insurance.status,'pending');
 assert.equal(evaluateDriverCompliance(rows.get('drivers/test'),{},Date.parse('2026-10-14T16:00:00Z')).documentHold,true);
 release(); await pending;
 const driver=rows.get('drivers/test');
 assert.equal(driver.documents.insurance.status,'approved');
 assert.equal(driver.documents.insurance.extractedFields.licenseNumber,undefined);
 assert.equal(driver.documents.insurance.approvedRecord.expirationDate,'2099-11-13');
 assert.equal(Object.keys(driver).some(key=>key.startsWith('documents.')),false);
 assert.equal(evaluateDriverCompliance(driver,{},Date.parse('2026-10-14T16:00:00Z')).documentHold,false);
});
test('older OCR completion cannot replace a newer approved upload',async()=>{
 seed(); let release; blockedOCR=new Promise(resolve=>{release=resolve;});
 const old=upload('200','older.jpg');
 await new Promise(resolve=>setImmediate(resolve));
 await upload('300','newest.jpg'); release(); await old;
 const record=rows.get('drivers/test').documents.insurance;
 assert.equal(record.storagePath,'driverDocuments/test/insurance/newest.jpg');
 assert.equal(record.approvedRecord.generation,'300');
 assert.equal(record.approvedRecord.storagePath,'driverDocuments/test/insurance/newest.jpg');
});

test('insurance without a vehicle identifier in the driver profile requires review', async()=>{
 seed(); delete rows.get('drivers/test').vehicle;
 await upload('400');
 assert.equal(rows.get('drivers/test').documents.insurance.status,'needs_review');
 assert.equal(rows.get('drivers/test').documents.insurance.approvedRecord.storagePath,'driverDocuments/test/insurance/old.jpg');
});
test('unrelated readable upload cannot be inferred as the requested document', async()=>{
 seed(); const original=text;
 try { text='This is a completely unrelated photograph with enough readable text to exceed the threshold.';
 await upload('400');
 assert.equal(rows.get('drivers/test').documents.insurance.status,'needs_review');
 } finally {text=original;}
});
test('late OCR cannot reverse a manual decline; a newer replacement can still be reviewed',async()=>{
 seed();let release;blockedOCR=new Promise(resolve=>{release=resolve;});const pending=upload('900','manual.jpg');
 await new Promise(resolve=>setImmediate(resolve));
 Object.assign(rows.get('drivers/test').documents.insurance,{status:'rejected',reviewReason:'Blurry photo',manualReviewId:'manual-1',manualReviewStoragePath:'driverDocuments/test/insurance/manual.jpg',manualReviewGeneration:'900'});
 release();await pending;
 assert.equal(rows.get('drivers/test').documents.insurance.status,'rejected');
 await upload('900','manual.jpg');assert.equal(rows.get('drivers/test').documents.insurance.status,'rejected');
 await upload('901','replacement.jpg');assert.equal(rows.get('drivers/test').documents.insurance.status,'approved');
});

test('a later license back upload preserves the front result and stores its own pointer', async () => {
 seed();
 const original = text;
 text = 'GEORGIA\nDRIVER LICENSE\nLICENSE NUMBER 123456789\nCLASS C\nISSUED 1/1/2020\nEXPIRES 1/1/2099\nNAME TEST DRIVER';
 try {
  const uploadLicense = (generation, file) => reviewUploadedDocument({
   bucket: 'fixture', contentType: 'image/jpeg', generation,
   storagePath: `driverDocuments/test/driverLicense/${file}`
  });
  await uploadLicense('1000', 'front-a.jpg');
  await uploadLicense('1001', 'back-b.jpg');
  await uploadLicense('999', 'back-a.jpg');
  const document = rows.get('drivers/test').documents.driverLicense;
  assert.equal(document.status, 'approved');
  assert.equal(document.storagePath, 'driverDocuments/test/driverLicense/front-a.jpg');
  assert.equal(document.backPath, 'driverDocuments/test/driverLicense/back-b.jpg');
  assert.equal(document.extractedFields.state, 'GA');
 } finally {
  text = original;
 }
});
