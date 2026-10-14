const test=require('node:test');const assert=require('node:assert/strict');
const {seatCount,seatCategory,normalizeSpecifications,exactLibraryEntry,resolveSpecifications,xlCapacityAllowed}=require('../src/services/vehicleSpecificationPolicy');
test('seating categories retain exact counts and never guess missing or ambiguous VIN capacity',()=>{
 for(const n of [4,5,6,7,8,9])assert.equal(seatCategory(n),n>=8?'8+':String(n));
 for(const n of [null,undefined,'5,7','8+','Unknown',0])assert.equal(seatCount(n),null);
 assert.throws(()=>normalizeSpecifications({seatCapacity:7,verified:true},'admin'),/evidence/);
});
test('seating conflicts block XL; five-seat luxury SUVs do not qualify for XL',()=>{
 const entry={vehicleId:'range-rover-sport',specifications:{verified:true,seatCapacity:5,luxuryClassification:'luxury',evidenceReference:'manufacturer'}};
 const spec=resolveSpecifications({vinReportedSeatCapacity:5},entry);assert.equal(spec.passengerCapacity,4);assert.equal(spec.luxuryClassification,'luxury');assert.equal(xlCapacityAllowed(spec),false);
 const conflict=resolveSpecifications({vinReportedSeatCapacity:7},entry);assert.equal(conflict.conflict,true);assert.equal(conflict.seatCapacity,null);assert.equal(xlCapacityAllowed(conflict),false);
 assert.equal(xlCapacityAllowed(resolveSpecifications({vinReportedSeatCapacity:7},null)),true);assert.equal(xlCapacityAllowed(resolveSpecifications({vinReportedSeatCapacity:9},null)),false);
});
test('specifications match independently of images and reject different years, trims and ambiguous variants',()=>{
 const base={vehicleId:'a',make:'Land Rover',model:'Range Rover Sport',yearStart:2024,yearEnd:2024,trim:'SE',specifications:{seatCapacity:5}};
 const vehicle={make:'LAND ROVER',model:'Range Rover Sport',year:2024,trim:'SE'};
 assert.equal(exactLibraryEntry([base],vehicle),base);assert.equal(exactLibraryEntry([base],{...vehicle,year:2023}),null);assert.equal(exactLibraryEntry([base],{...vehicle,trim:'Other'}),null);
 assert.equal(exactLibraryEntry([base,{...base,vehicleId:'b',specifications:{seatCapacity:7}}],vehicle),null);
});
