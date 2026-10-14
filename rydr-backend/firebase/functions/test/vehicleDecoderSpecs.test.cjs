const test=require('node:test');const assert=require('node:assert/strict');const Module=require('node:module');
const records=new Map();let calls=0,seats='5';const vin='SAL1P9EU0RA170245';
const load=Module._load;Module._load=function(request,parent){
 if(parent?.filename.endsWith('vehicleDecoderService.js')){
  if(request==='../admin')return {db:{collection:()=>({doc:id=>({get:async()=>({exists:records.has(id),data:()=>records.get(id)}),set:async data=>records.set(id,data)})})},Timestamp:{now:()=>123}};
  if(request==='node-fetch')return async()=>{calls++;return {ok:true,json:async()=>({Results:[{Make:'LAND ROVER',Model:'Range Rover Sport',ModelYear:'2024',Seats:seats,SeatRows:'2',ErrorCode:'0'}]})};};
 }
 return load.apply(this,arguments);
};const {VehicleDecoderService}=require('../lib/services/vehicleDecoderService');Module._load=load;
test('old VIN caches refresh once and retain manufacturer-reported seats and rows',async()=>{
 records.clear();calls=0;seats='5';records.set(vin,{vin,make:'LAND ROVER'});const service=new VehicleDecoderService();const decoded=await service.decode(vin);
 assert.equal(decoded.seatCapacity,5);assert.equal(decoded.seatRows,2);assert.equal(decoded.raw.Seats,'5');await service.decode(vin);assert.equal(calls,1);
});
test('missing seating remains unknown and does not trigger endless VIN refetches',async()=>{
 records.clear();calls=0;seats='';const service=new VehicleDecoderService();const decoded=await service.decode(vin);assert.equal(decoded.seatCapacity,null);await service.decode(vin);assert.equal(calls,1);
});
