const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),ts=require('typescript');
require.extensions['.ts']=(mod,file)=>mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,file);
const {latestDriverDocument,uploadedDocumentPath,driverDocumentReviewItems}=require('../lib/driverDocumentReview.ts');
test('a flagged renewal remains visible even while approved proof keeps the account current',()=>{
 const d={documents:{insurance:{status:'needs_review',reviewReason:'VIN unreadable',storagePath:'driverDocuments/driver/insurance/new.jpg',approvedRecord:{status:'approved',expirationDate:'2027-01-01'}}}};
 const row=driverDocumentReviewItems(d).find(x=>x.kind==='insurance');assert.equal(row.attention,true);assert.equal(row.record.storagePath,'driverDocuments/driver/insurance/new.jpg');assert.equal(row.record.reviewReason,'VIN unreadable');assert.equal(row.record.approvedRecord.status,'approved');
});
test('backend submission paths are available before OCR provides a download URL',()=>{
 const d={licenseSubmission:{frontStoragePath:'driverDocuments/driver/driverLicense/front.jpg',backStoragePath:'driverDocuments/driver/driverLicense/back.jpg'},vehicleDocumentSubmission:{insuranceStoragePath:'driverDocuments/driver/insurance/single.jpg'}};
 assert.equal(uploadedDocumentPath(d,'driver','driverLicense','front'),d.licenseSubmission.frontStoragePath);assert.equal(uploadedDocumentPath(d,'driver','driverLicense','back'),d.licenseSubmission.backStoragePath);
 const insurance=driverDocumentReviewItems(d).find(x=>x.kind==='insurance');assert.equal(insurance.status,'awaiting_automation');assert.equal(insurance.attention,true);
});
test('previews cannot read another driver, kind, arbitrary side or traversal path',()=>{
 for(const path of ['driverDocuments/other/insurance/a.jpg','driverDocuments/driver/registration/a.jpg','driverDocuments/driver/insurance/../a.jpg'])assert.equal(uploadedDocumentPath({documents:{insurance:{storagePath:path}}},'driver','insurance','front'),null);
 assert.equal(uploadedDocumentPath({},'driver','unknown','front'),null);assert.equal(uploadedDocumentPath({},'driver','insurance','unknown'),null);
});
test('legacy dotted pointers remain discoverable and approved documents are not flagged',()=>{
 const d={'documents.registration.storagePath':'driverDocuments/driver/registration/a.jpg','documents.registration.status':'approved'};
 assert.equal(latestDriverDocument(d,'registration').storagePath,'driverDocuments/driver/registration/a.jpg');assert.equal(driverDocumentReviewItems(d).find(x=>x.kind==='registration').attention,false);
});
test('automated processing is separate from a manual review result',()=>{
 const row=driverDocumentReviewItems({documents:{insurance:{status:'pending',storagePath:'driverDocuments/driver/insurance/a.jpg'}}}).find(x=>x.kind==='insurance');assert.equal(row.processing,true);assert.equal(row.attention,false);
});
