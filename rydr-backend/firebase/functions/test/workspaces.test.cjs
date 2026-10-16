const {test}=require('node:test');const assert=require('node:assert/strict');
process.env.GCLOUD_PROJECT='demo-rydr-workspaces';
const {runInWorkspace}=require('../lib/services/workspaceRuntime');
const {db}=require('../lib/admin');const functions=require('../lib/index');
test('every database trigger has a Live Beta clone bound to the named database',()=>{
 let count=0;for(const [name,handler]of Object.entries(functions)){
 if(!handler?.__endpoint?.eventTrigger?.eventFilters?.database)continue;
 const clone=functions.liveBeta[name];assert.ok(clone,name+' missing live clone');assert.equal(handler.__endpoint.eventTrigger.eventFilters.database,'(default)');assert.equal(clone.__endpoint.eventTrigger.eventFilters.database,'live-beta');count++;
 }assert.ok(count>15,'expected Firestore trigger coverage');
});
test('callable, HTTP, and scheduled handlers retain independent deployment endpoints',()=>{
 for(const name of ['decodeVin','deleteDriverVehicle','editVehicleLibraryBackground','queueMondayDriverPayouts','onPaidRidePromotionSettlement'])assert.ok(functions.liveBeta[name]?.__endpoint,name);
 assert.notEqual(functions.liveBeta.decodeVin,functions.decodeVin);assert.equal(functions.liveBeta.onDocumentUploadedForReview,undefined,'shared Storage trigger must not duplicate document review');
});
test('lazy Firestore service follows current invocation and isolates library assets',()=>{
 const {storagePathFor}=require('../lib/services/vehicleLibraryService');
 for(const workspace of ['test','live-beta'])runInWorkspace(workspace,()=>{
  assert.equal(db.databaseId,workspace==='test'?'(default)':'live-beta');
  assert.ok(storagePathFor('Land Rover','Range Rover',2024,'silver.png').startsWith('vehicle-library/'+workspace+'/'));
 });
});
