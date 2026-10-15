const test = require('node:test'), assert = require('node:assert/strict'), Module = require('node:module');
const {bindPrestineLibrary}=require('../lib/services/prestineLibraryPolicy');
const {resolveSpecifications}=require('../lib/services/vehicleSpecificationPolicy');
let row, entry, writes, replacement;
const ref={get:async()=>({data:()=>structuredClone(row)})};
const db={collection:()=>({doc:()=>({get:async()=>({data:()=>({enabled:false})})})}),runTransaction:async fn=>fn({get:async()=>({data:()=>structuredClone(row)}),update:(_ref,data)=>{writes++;row={...row,...structuredClone(data)};}})};
const load=Module._load;
Module._load=function(request,parent){
 if(parent?.filename.endsWith('refreshDriverVehicleEligibility.js')){
  if(request==='../admin')return {db};
  if(request==='./vehicleSpecificationsService')return {getVehicleSpecificationMatch:async vehicle=>{const match={libraryEligibility:bindPrestineLibrary(vehicle,entry),specifications:resolveSpecifications(vehicle,entry),eligibleRideTypes:entry?.eligibleRideTypes??[]};if(replacement)row.vehicle=replacement;return match;}};
 }return load.apply(this,arguments);
};
const {refreshDriverVehicleEligibility}=require('../lib/services/refreshDriverVehicleEligibility');Module._load=load;
function seed(){writes=0;replacement=null;row={vehicle:{vin:'SAL1P9EU0RA170245',make:'Land Rover',model:'Range Rover Sport',year:2024},qualifiedRideTypes:['Rydr Go'],supportedRideTypes:['Rydr Go'],selectedRideTypes:['Rydr Go']};entry={vehicleId:'rr',make:'Land Rover',model:'Range Rover Sport',yearStart:2024,yearEnd:2024,bodyStyle:'suv',eligibleRideTypes:['Rydr Go','Rydr Prestine'],specifications:{verified:true,seatCapacity:5,luxuryClassification:'luxury'}};}
test('refresh enables Prestine without a manual review and converges without trigger write loops',async()=>{seed();await refreshDriverVehicleEligibility(ref);assert.deepEqual(row.qualifiedRideTypes,['Rydr Go','Rydr Prestine SUV']);assert.equal(row.premiumReview,undefined);assert.equal(row.premiumEligibility.prestine.eligible,true);assert.deepEqual(row.selectedRideTypes,['Rydr Go']);const first=writes;await refreshDriverVehicleEligibility(ref);assert.equal(writes,first);});
test('library revocation removes premium selection while preserving Go',async()=>{seed();await refreshDriverVehicleEligibility(ref);row.selectedRideTypes=['Rydr Go','Rydr Prestine SUV'];entry.eligibleRideTypes=['Rydr Go'];await refreshDriverVehicleEligibility(ref);assert.deepEqual(row.qualifiedRideTypes,['Rydr Go']);assert.deepEqual(row.selectedRideTypes,['Rydr Go']);});
test('switching vehicles during a refresh cannot overwrite or qualify the replacement',async()=>{seed();replacement={vin:'1GYS4DKL0PR123456',make:'Chevrolet',model:'Equinox',year:2022};assert.equal(await refreshDriverVehicleEligibility(ref),null);assert.equal(writes,0);assert.equal(row.vehicle.model,'Equinox');});
