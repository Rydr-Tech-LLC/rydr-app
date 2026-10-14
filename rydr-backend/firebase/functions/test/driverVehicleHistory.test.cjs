const test=require('node:test');
const assert=require('node:assert/strict');
const Module=require('node:module');
const records=new Map();let timestamp=0;
function ref(path){return {collection:name=>({doc:id=>ref(`${path}/${name}/${id}`)}),create:async data=>{if(records.has(path))throw {code:6};records.set(path,data);}};}
const load=Module._load;
Module._load=function(request,parent){
 if(parent?.filename.endsWith('driverVehicleHistory.js')){
  if(request==='firebase-functions/v2/firestore')return {onDocumentWritten:(_opts,handler)=>handler};
  if(request==='../admin')return {db:{collection:name=>({doc:id=>ref(`${name}/${id}`)})},FieldValue:{serverTimestamp:()=>++timestamp}};
 }
 return load.apply(this,arguments);
};
const {onDriverVehicleHistoryChanged}=require('../lib/triggers/driverVehicleHistory');Module._load=load;
const event=(before,after,id='event-1')=>({id,time:'2026-10-14T18:00:00Z',params:{uid:'driver'},data:{before:{data:()=>before},after:{data:()=>after}}});
test('plate edits retain both plates and retries leave existing archive records unchanged',async()=>{
 records.clear();const before={vehicle:{vin:'SAMEVIN',make:'Honda',plate:'OLD'}};const after={vehicle:{vin:'SAMEVIN',make:'Honda',plate:'NEW'}};
 await onDriverVehicleHistoryChanged(event(before,after));const initial=[...records.values()];assert.equal(initial.length,2);assert.deepEqual(initial.map(v=>v.vehicle.plate),['OLD','NEW']);
 await onDriverVehicleHistoryChanged(event(before,after));assert.deepEqual([...records.values()],initial);
});
test('removed saved vehicles retain their VIN and plate',async()=>{
 records.clear();await onDriverVehicleHistoryChanged(event({savedVehicles:{saved:{vin:'VIN123',plate:'SAFE1'}}},{savedVehicles:{}},'event-2'));
 assert.equal(records.size,1);const row=[...records.values()][0];assert.equal(row.vehicleId,'saved');assert.equal(row.vehicle.vin,'VIN123');assert.equal(row.vehicle.plate,'SAFE1');
});
test('unrelated driver updates do not add history records',async()=>{
 records.clear();await onDriverVehicleHistoryChanged(event({vehicle:{vin:'VIN123',plate:'SAFE1'},online:false},{vehicle:{vin:'VIN123',plate:'SAFE1'},online:true},'event-3'));assert.equal(records.size,0);
});
