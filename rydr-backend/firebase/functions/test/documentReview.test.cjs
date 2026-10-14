const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const rows = new Map();
let blockedOCR;
let text = 'INSURANCE POLICY\nPolicy Number: POLICY123456\nInsured: TEST DRIVER\nExpiration: 11/13/2026\nLiability coverage effective\nVIN: SAL1P9EU0RA170245';
function merge(a,b) { for (const [k,v] of Object.entries(b)) { if (v && typeof v === 'object' && !Array.isArray(v)) { a[k] ??= {}; merge(a[k],v); } else a[k]=v; } return a; }
function ref(key) { return { collection: n=>({doc:id=>ref(`${key}/${n}/${id}`)}), get:async()=>({exists:rows.has(key),data:()=>rows.has(key)?structuredClone(rows.get(key)):undefined}), set:async(data,options)=>rows.set(key,options?.merge?merge(rows.get(key)??{},data):data) }; }
const db={collection:n=>({doc:id=>ref(`${n}/${id}`)}),runTransaction:async fn=>{const writes=[]; await fn({get:r=>r.get(),set:(r,d,o)=>writes.push(()=>r.set(d,o))}); for(const w of writes) await w();},batch:()=>({})};
const load=Module._load;
Module._load=function(request,parent) {
 if(request==='../admin' && parent?.filename.endsWith('documentReviewService.js')) return {db,FieldValue:{serverTimestamp:()=> 'server-time'}};
 if(request==='node-fetch' && parent?.filename.endsWith('documentReviewService.js')) return async url=>{
  if(String(url).includes('metadata.google')) return {ok:true,json:async()=>({access_token:'fixture-only'})};
  if(blockedOCR) {const wait=blockedOCR; blockedOCR=null; await wait;}
  return {ok:true,json:async()=>({responses:[{fullTextAnnotation:{text}}]})};
 };
 return load.apply(this,arguments);
};
const {reviewUploadedDocument}=require('../lib/services/documentReviewService');
Module._load=load;
const {evaluateDriverCompliance}=require('../src/services/driverCompliancePolicy');
function seed() { rows.clear(); rows.set('drivers/test',{vehicle:{vin:'SAL1P9EU0RA170245'},documents:{insurance:{status:'approved',expirationDate:'2026-10-13',storagePath:'driverDocuments/test/insurance/old.jpg',generation:'100'},driverLicense:{status:'approved',expirationDate:'2027-01-01'},registration:{status:'approved',expirationDate:'2027-01-01'}}}); }
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
 assert.equal(driver.documents.insurance.approvedRecord.expirationDate,'2026-11-13');
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
