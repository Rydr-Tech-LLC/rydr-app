const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const rows = new Map();
const DELETE = Symbol('delete');
function ref(key) {return {key};}
const db = { collection: name => ({doc:id=>ref(`${name}/${id}`), where:()=>({query:name})}), runTransaction:async fn=>{
 const writes=[];
 await fn({get:async r=>r.query ? {docs:[...(rows.get('rides')??[])].map(data=>({data:()=>data}))} : {exists:rows.has(r.key),data:()=>rows.get(r.key)}, update:(r,data)=>writes.push(()=>{
 const row=rows.get(r.key); for(const [k,v] of Object.entries(data)) {const parts=k.split('.');let node=row; for(const part of parts.slice(0,-1)) node=node[part]??={}; if(v===DELETE)delete node[parts.at(-1)];else node[parts.at(-1)]=v;}
 }),set:(r,data)=>writes.push(()=>{rows.set(r.key,{...(rows.get(r.key)??{}),...data});})});
 for(const write of writes)write();
}};
const load=Module._load;
Module._load=function(request,parent){if(request==='../admin'&&parent?.filename.endsWith('driverGarageService.js'))return {db,FieldValue:{serverTimestamp:()=>123,delete:()=>DELETE}};return load.apply(this,arguments);};
const {addSavedDriverVehicle,deleteSavedDriverVehicle}=require('../lib/services/driverGarageService');Module._load=load;
const current={vin:'CURRENTVIN0000001',make:'Honda',model:'Accord',year:2020,color:'White',plate:'CURRENT'};
const added={vin:'SAL1P9EU0RA170245',make:'Land Rover',model:'Range Rover',year:2024,color:'Black',plate:'SECOND'};
function seed(){rows.clear();rows.set('drivers/driver',{vehicle:{...current},savedVehicles:{},selectedRideTypes:['Rydr Go'],documents:{insurance:{status:'approved'}},isApproved:true});}
test('adding a vehicle preserves the current vehicle, documents and ride setup',async()=>{
 seed(); const id=await addSavedDriverVehicle('driver',added,{});const driver=rows.get('drivers/driver');
 assert.deepEqual(driver.vehicle,current);assert.deepEqual(driver.selectedRideTypes,['Rydr Go']);assert.equal(driver.documents.insurance.status,'approved');assert.equal(driver.savedVehicles[id].vin,added.vin);assert.equal(driver.savedVehicles[id].documentsStatus,'required');
});
test('duplicate current and saved vehicles are rejected without replacement',async()=>{
 seed();await assert.rejects(addSavedDriverVehicle('driver',current,{}),/already/);const id=await addSavedDriverVehicle('driver',added,{});await assert.rejects(addSavedDriverVehicle('driver',added,{}),/already/);assert.deepEqual(Object.keys(rows.get('drivers/driver').savedVehicles),[id]);
});
test('deleting a saved vehicle preserves current vehicle and approval',async()=>{
 seed();const id=await addSavedDriverVehicle('driver',added,{});await deleteSavedDriverVehicle('driver',id);assert.deepEqual(rows.get('drivers/driver').savedVehicles,{});assert.deepEqual(rows.get('drivers/driver').vehicle,current);assert.equal(rows.get('drivers/driver').isApproved,true);
});
test('current vehicle cannot be deleted online or during an assigned ride',async()=>{
 seed();rows.get('drivers/driver').isOnline=true;await assert.rejects(deleteSavedDriverVehicle('driver','current',current.vin,current.plate),/offline/);rows.get('drivers/driver').isOnline=false;rows.set('rides',[{status:'accepted'}]);await assert.rejects(deleteSavedDriverVehicle('driver','current',current.vin,current.plate),/assigned/);assert.deepEqual(rows.get('drivers/driver').vehicle,current);
});
test('current deletion removes driving eligibility and preserves other saved vehicles',async()=>{
 seed();const id=await addSavedDriverVehicle('driver',added,{});await deleteSavedDriverVehicle('driver','current',current.vin,current.plate);const driver=rows.get('drivers/driver');assert.equal(driver.vehicle,undefined);assert.equal(driver.canGoOnline,false);assert.equal(driver.driverApprovalStatus,'needs_attention');assert.equal(driver.savedVehicles[id].vin,added.vin);assert.deepEqual(driver.selectedRideTypes,[]);
});
test('stale deletion cannot remove a vehicle changed by another session',async()=>{
 seed();await assert.rejects(deleteSavedDriverVehicle('driver','current','OTHER',current.plate),/changed/);assert.deepEqual(rows.get('drivers/driver').vehicle,current);
});
