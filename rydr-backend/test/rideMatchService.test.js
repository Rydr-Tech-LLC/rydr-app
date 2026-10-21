const test = require("node:test");
const assert = require("node:assert/strict");
const { publicDriverProjection, driverCanFinishBeforeScheduledPickup } = require("../src/services/rideMatchService");
const { hasCurrentOnlinePresence } = require("../src/services/driverPresenceService");

test("match candidates expose only rider-safe display data", () => {
  const projection = publicDriverProjection({
    displayName: "Taylor Driver",
    driverSex: "female",
    email: "private@example.com",
    phoneNumber: "+15555550123",
    profilePhotoURL: "https://example.com/profile.jpg",
    vehicle: { color: "Black", year: 2025, make: "Toyota", model: "Camry", licensePlate: "PRIVATE" },
    rating: 4.9,
    ratingCount: 31,
    completedRideCount: 84,
    acceptanceRate: 96,
    compliments: ["Safe driver", "Great conversation"]
  }, { latitude: 33.749, longitude: -84.388 });

  assert.equal(projection.displayName, "Taylor");
  assert.equal(projection.vehicleSummary, "Black 2025 Toyota Camry");
  assert.deepEqual(projection.approximateLocation, { lat: 33.749, lng: -84.388 });
  assert.equal(projection.driverSex, undefined);
  assert.equal(projection.email, undefined);
  assert.equal(projection.phoneNumber, undefined);
  assert.equal(projection.licensePlate, undefined);
});

test("match candidate projection supplies stable display fallbacks", () => {
  const projection = publicDriverProjection({}, { latitude: 1, longitude: 2 });
  assert.equal(projection.displayName, "Rydr Driver");
  assert.equal(projection.vehicleSummary, "Verified Rydr vehicle");
  assert.equal(projection.rating, 5);
});

test("match candidate projection prefers the driver's real first name over a username", () => {
  const projection = publicDriverProjection({
    firstName: "Khristoffer",
    lastName: "Nunnally",
    displayName: "nunster2005"
  }, { latitude: 1, longitude: 2 });
  assert.equal(projection.displayName, "Khristoffer");
});

test("online presence must have a current backend lease", () => {
  const now = Date.UTC(2026, 9, 9, 12);
  assert.equal(hasCurrentOnlinePresence({
    isOnline: true,
    availabilityStatus: "available",
    presenceExpiresAt: { toMillis: () => now + 60_000 }
  }, now), true);
  assert.equal(hasCurrentOnlinePresence({
    isOnline: true,
    availabilityStatus: "available",
    presenceExpiresAt: { toMillis: () => now - 1 }
  }, now), false);
});

test("live matching protects enough time to finish and reach a scheduled pickup", async () => {
  const now = Date.UTC(2026, 9, 9, 12);
  const lockDoc = {
    id: "scheduled-1",
    data: () => ({
      scheduledRideId: "scheduled-1",
      scheduledPickupAt: now + 45 * 60 * 1000,
      pickupCoordinate: { lat: 33.75, lng: -84.39 }
    })
  };
  const db = {
    collection: () => ({
      doc: () => ({
        collection: () => ({
          where: () => ({ limit: () => ({ get: async () => ({ docs: [lockDoc] }) }) })
        })
      })
    })
  };
  const durations = [5 * 60, 10 * 60];
  const allowed = await driverCanFinishBeforeScheduledPickup({
    candidate: { id: "driver-1", location: { latitude: 33.7, longitude: -84.4 } },
    db,
    pickup: { latitude: 33.71, longitude: -84.41 },
    dropoff: { latitude: 33.73, longitude: -84.4 },
    tripDurationSeconds: 15 * 60,
    routeProvider: async () => ({ route: { durationSeconds: durations.shift() } }),
    nowMillis: now
  });
  assert.equal(allowed, true);
});

test('pickup ETA uses the driver-to-pickup road route, independently of trip duration', async()=>{
 const {pickupEstimate}=require('../src/services/rideMatchService');
 const origin={latitude:33.7,longitude:-84.4}, pickup={latitude:33.8,longitude:-84.3};
 const eta=await pickupEstimate({candidate:{location:origin},pickup,nowMillis:1000,routeProvider:async request=>{assert.deepEqual(request.origin,origin);assert.deepEqual(request.destination,pickup);return{route:{durationSeconds:960,distanceMeters:16093.44}}}});
 assert.equal(eta.durationSeconds,960);assert.equal(eta.distanceMiles,10);assert.equal(eta.calculatedAtMillis,1000);
});
test('pickup route failure or invalid duration reports unavailable rather than a misleading estimate',async()=>{
 const {pickupEstimate}=require('../src/services/rideMatchService');const input={candidate:{location:{}},pickup:{},nowMillis:0};
 assert.equal(await pickupEstimate({...input,routeProvider:async()=>{throw Error('offline')}}),null);
 assert.equal(await pickupEstimate({...input,routeProvider:async()=>({route:{durationSeconds:NaN,distanceMeters:1}})}),null);
});

test('a stalled pickup ETA provider cannot hold the match request open indefinitely',async()=>{
 const {pickupEstimate}=require('../src/services/rideMatchService');
 const result=await pickupEstimate({candidate:{location:{}},pickup:{},nowMillis:0,timeoutMillis:5,routeProvider:()=>new Promise(()=>{})});
 assert.equal(result,null);
});

test("sessions rank by saved rider preference and canonical driver disclosures", async () => {
  const {createRideMatchSession} = require('../src/services/rideMatchService');
  const now = require('../src/config/firebase').admin.firestore.Timestamp.now();
  const reads = [], writes = [];
  const drivers = Object.fromEntries(['a','b'].map((id,i)=>[id, {
    driverApprovalStatus:'approved',driverSignupCompleted:true,driverSex:i?'female':'male',
    rateCardUpdatedAt:now,tierRates:{'Rydr Go':{minimumFare:5,perMile:1,perMinute:0.2}},eligibleRideTypes:['Rydr Go']
  }]));
  function ref(path) {
    return {path,id:path.split('/').at(-1),collection:key=>ref(`${path}/${key}`),doc:(id='session')=>ref(`${path}/${id}`),where:()=>ref(path),limit:()=>ref(path),
      async get() {
        reads.push(path);
        if(path==='publicDriverProfiles') return {docs:Object.keys(drivers).map(id=>({id,data:()=>({isOnline:true,driverSex:'female',approximateLocation:{lat:33.749,lng:-84.388}})}))};
        if(path.endsWith('/scheduledRideLocks')) return {docs:[]};
        const value=path==='riders/authenticated-rider/ridePreferences/current'?{genderPreference:'Female'}
          :path==='platformConfig/stripeRuntime'?{status:'ready',mode:'test'}
          :path.startsWith('drivers/')?drivers[path.split('/')[1]]
          :path.startsWith('driver_status/')?{isOnline:true,availabilityStatus:'available',presenceExpiresAt:{toMillis:()=>now.toMillis()+60000},location:{lat:33.749,lng:-84.388}}:{};
        return {id:this.id,exists:true,data:()=>value};
      },async create(value){writes.push(value);}
    };
  }
  const db={collection:key=>ref(key),getAll:(...refs)=>Promise.all(refs.map(r=>r.get()))};
  const result=await createRideMatchSession({riderId:'authenticated-rider',now,db,
    payload:{rideType:'Rydr Go',pickupCoordinate:{lat:33.749,lng:-84.388},dropoffCoordinate:{lat:33.77,lng:-84.36},genderPreference:'Male'},
    routeProvider:async()=>({route:{distanceMeters:5000,durationSeconds:600}})});
  assert.deepEqual(result.candidates.map(c=>c.driverId),['b','a']);
  assert.ok(reads.includes('riders/authenticated-rider/ridePreferences/current'));
  assert.deepEqual(writes[0].candidateIds,['b','a']);
});
