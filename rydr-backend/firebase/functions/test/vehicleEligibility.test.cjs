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
