const test=require('node:test');const assert=require('node:assert/strict');
const {evaluateVehicleEligibility}=require('../lib/services/vehicleEligibilityService');
test('2024 Land Rover Range Rover Sport does not gain XL or premium from make/model alone',()=>{
 for(const make of ['LAND ROVER','Land Rover','landrover']){
 const vehicle={make,model:'Range Rover Sport',year:2024,bodyStyle:'suv',color:'Silver',fuelType:'Gasoline'};
 const result=evaluateVehicleEligibility({...vehicle,vehicle,libraryRideTypes:[],executiveConfig:{enabled:false}});
 assert.equal(result.rideTypes.includes('Rydr XL'),false);assert.equal(result.rideTypes.some(type=>/Prestine/.test(type)),false);
 }
});

test('a reviewed five-seat luxury library candidate can offer Go but never XL',()=>{
 const vehicle={make:'Land Rover',model:'Range Rover Sport',year:2024,specifications:{seatCapacity:5,source:'reviewed_library'}};
 const result=evaluateVehicleEligibility({make:vehicle.make,model:vehicle.model,fuelType:'Gasoline',vehicle,libraryRideTypes:['Rydr Go','Rydr XL']});
 assert.deepEqual(result.rideTypes,['Rydr Go']);
});
const {bindPrestineLibrary}=require('../lib/services/prestineLibraryPolicy');
const {resolveSpecifications}=require('../lib/services/vehicleSpecificationPolicy');
test('selected five-seat luxury SUV gets Go and Prestine SUV automatically, never XL',()=>{
 const vehicle={vin:'SAL1P9EU0RA170245',make:'LAND ROVER',model:'Range Rover Sport',year:2024,trim:'P360 SE',bodyStyle:'suv'};
 const entry={vehicleId:'range-rover',make:vehicle.make,model:vehicle.model,yearStart:2023,yearEnd:2026,bodyStyle:'suv',eligibleRideTypes:['Rydr Go','Rydr XL','Rydr Prestine'],specifications:{verified:true,seatCapacity:5,luxuryClassification:'luxury'}};
 Object.assign(vehicle,{libraryEligibility:bindPrestineLibrary(vehicle,entry),specifications:resolveSpecifications(vehicle,entry)});
 const result=evaluateVehicleEligibility({...vehicle,vehicle,libraryRideTypes:entry.eligibleRideTypes});
 assert.deepEqual(result.rideTypes,['Rydr Go','Rydr Prestine SUV']);
 entry.specifications.seatCapacity=7;vehicle.specifications=resolveSpecifications(vehicle,entry);
 assert.deepEqual(evaluateVehicleEligibility({...vehicle,vehicle,libraryRideTypes:entry.eligibleRideTypes}).rideTypes,['Rydr Go','Rydr XL','Rydr Prestine SUV']);
});
