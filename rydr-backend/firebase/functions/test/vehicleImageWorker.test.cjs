const { test } = require('node:test');
const assert = require('node:assert/strict');
const records = new Map(), files = new Map();
let searchCount=0, aiCount=0, license='CC0', whiteBackground=true, aiFails=false, noCredits=false;
function assign(path, update, merge) {
  const data=merge ? structuredClone(records.get(path) ?? {}) : {};
  for (const [key,value] of Object.entries(update)) {
    const parts=key.split('.'); let target=data;
    for (const part of parts.slice(0,-1)) target=target[part] ??= {};
    const leaf=parts.at(-1);
    target[leaf]=value?.op==='increment' ? (target[leaf]??0)+value.n : value?.op==='union' ? [...new Set([...(target[leaf]??[]),...value.items])] : value;
  }
  records.set(path,data);
}
function ref(path) { return {path,id:path.split('/').at(-1),collection:name=>collection(`${path}/${name}`),get:async()=>({exists:records.has(path),data:()=>structuredClone(records.get(path))}),create:async data=>{if(records.has(path))throw{code:6};assign(path,data,false);}}; }
function collection(path) { return {doc:id=>ref(`${path}/${id}`),get:async()=>({docs:[...records.keys()].filter(key=>key.startsWith(`${path}/`)&&key.split('/').length===path.split('/').length+1).map(key=>({...ref(key),ref:ref(key)}))})}; }
const db={collection,runTransaction:async fn=>fn({get:r=>r.get(),create:(r,d)=>assign(r.path,d,false),delete:r=>records.delete(r.path),update:(r,d)=>assign(r.path,d,true),set:(r,d,o)=>assign(r.path,d,o?.merge)})};
const adminPath=require.resolve('../lib/admin');
require.cache[adminPath]={id:adminPath,filename:adminPath,loaded:true,exports:{db,FieldValue:{serverTimestamp:()=>123,increment:n=>({op:'increment',n}),arrayUnion:(...items)=>({op:'union',items})},storage:{bucket:()=>({name:'test-bucket',file:path=>({save:async(data,opts)=>files.set(path,{data,opts}),makePublic:async()=>{},delete:async()=>files.delete(path)})})}}};
const fetchPath=require.resolve('node-fetch');
require.cache[fetchPath]={id:fetchPath,filename:fetchPath,loaded:true,exports:async(url,opts)=>{
 if(url.startsWith('https://commons.wikimedia.org/w/api.php')){
  searchCount++;
  return {ok:true,json:async()=>({query:{pages:{1:{title:'File:2024 Range Rover Sport P360 SE.jpg',imageinfo:[{width:1600,height:900,mime:'image/jpeg',url:'https://upload.wikimedia.org/car.jpg',descriptionurl:'https://commons.wikimedia.org/wiki/File:Car.jpg',extmetadata:{LicenseShortName:{value:license},ImageDescription:{value:'2024 Range Rover Sport P360 SE Black'}}}]}}}})};
 }
 if(url==='https://upload.wikimedia.org/car.jpg'){
  assert.equal(opts.redirect,'error'); assert.equal(opts.size,6*1024*1024);
  return {ok:true,buffer:async()=>Buffer.from([0xff,0xd8,0xff,0x00]),headers:{get:()=> 'image/jpeg'}};
 }
 if(url==='https://api.openai.com/v1/responses'){
  aiCount++;assert.equal(JSON.parse(opts.body).store,false);
  if(noCredits)return{ok:false,status:429,json:async()=>({error:{code:'credit_balance_exhausted'}})};
  if(aiFails)return{ok:false,status:503};
  return {ok:true,json:async()=>({output:[{content:[{type:'output_text',text:JSON.stringify({vehicleMatches:true,yearSupported:true,trimSupported:true,colorMatches:true,whiteBackground,singleVehicle:true,noWatermark:true,confidence:0.99,reason:'Verified'})}]}]})};
 }
 throw new Error(`Unexpected URL ${url}`);
}};
const {enqueueImageJob,processImageJob,imageJobId,updateWaitingDrivers}=require('../lib/services/vehicleImageAcquisition');
const {buildVehicleId}=require('../lib/services/vehicleLibraryService');
const query={make:'LAND ROVER',model:'Range Rover Sport',year:2024,trim:'P360 SE',color:'Black',bodyStyle:'suv'};
const jobId=imageJobId(query);
function reset(){records.clear();files.clear();searchCount=0;aiCount=0;license='CC0';whiteBackground=true;aiFails=false;noCredits=false;delete process.env.VEHICLE_IMAGE_DAILY_LIMIT;}
test('imports once and propagates to matching waiters, including later registrations',async()=>{
 reset();records.set('drivers/a',{vehicle:{...query}});records.set('drivers/b',{vehicle:{...query,color:'White'}});
 await enqueueImageJob(query,'a');await enqueueImageJob(query,'a');await enqueueImageJob(query,'b');
 await processImageJob(jobId,'test-key');await processImageJob(jobId,'test-key');
 const job=records.get(`vehicleImageJobs/${jobId}`);
 assert.equal(job.status,'completed');assert.equal(searchCount,1);assert.equal(aiCount,1);assert.equal(files.size,1);
 const entry=records.get(`vehicleLibrary/${job.vehicleId}`);
 assert.equal(entry.colorImages.Black,job.storagePath);assert.equal(entry.imageSources.Black.license,'CC0');assert.deepEqual(entry.availableColors,['Black']);
 await updateWaitingDrivers(jobId,job);
 assert.equal(records.get('drivers/a').vehicle.imageURL,job.imageUrl);assert.equal(records.get('drivers/a').vehicle.imageUrl,job.imageUrl);assert.equal(records.get('drivers/b').vehicle.imageUrl,undefined);
 records.set('drivers/c',{vehicle:{...query}});await enqueueImageJob(query,'c');assert.equal(records.get('drivers/c').vehicle.imageUrl,job.imageUrl);
});
test('uncertain images become reviews without publication',async()=>{
 reset();whiteBackground=false;await enqueueImageJob(query);await processImageJob(jobId,'test-key');
 const job=records.get(`vehicleImageJobs/${jobId}`);assert.equal(job.status,'needs_review');assert.equal(job.candidates[0].assessment.whiteBackground,false);assert.equal(files.size,0);
});
test('attribution licenses are flagged before AI charges',async()=>{
 reset();license='CC BY-SA 4.0';await enqueueImageJob(query);await processImageJob(jobId,'test-key');assert.equal(records.get(`vehicleImageJobs/${jobId}`).status,'needs_review');assert.equal(aiCount,0);assert.equal(files.size,0);
});
test('concurrent curated images cannot be overwritten',async()=>{
 reset();const id=buildVehicleId(query.make,query.model,query.year,query.year,query.trim);
 records.set(`vehicleLibrary/${id}`,{colorImages:{Black:'vehicle-library/curated.jpg'},availableColors:['Black']});
 await enqueueImageJob(query);await processImageJob(jobId,'test-key');const job=records.get(`vehicleImageJobs/${jobId}`);
 assert.equal(job.status,'completed');assert.equal(job.storagePath,'vehicle-library/curated.jpg');assert.equal(files.size,0);
});
test('AI failures and missing configuration yield reviews',async()=>{
 for(const key of ['test-key','']){reset();aiFails=true;await enqueueImageJob(query);await processImageJob(jobId,key);assert.equal(records.get(`vehicleImageJobs/${jobId}`).status,'needs_review');assert.equal(files.size,0);}
});
test('daily limit bounds provider calls',async()=>{
 reset();process.env.VEHICLE_IMAGE_DAILY_LIMIT='1';await enqueueImageJob(query);await processImageJob(jobId,'test-key');
 const other={...query,color:'White'};await enqueueImageJob(other);await processImageJob(imageJobId(other),'test-key');
 assert.equal(searchCount,1);assert.match(records.get(`vehicleImageJobs/${imageJobId(other)}`).reason,/Daily/);
});
test('exact/custom photos already on a driver are preserved',async()=>{
 reset();records.set('drivers/a',{vehicle:{...query,imageUrl:'https://custom/image.jpg'}});await enqueueImageJob(query,'a');await processImageJob(jobId,'test-key');await updateWaitingDrivers(jobId,records.get(`vehicleImageJobs/${jobId}`));assert.equal(records.get('drivers/a').vehicle.imageUrl,'https://custom/image.jpg');
});

test('removed library images are flagged rather than reusing stale completed URLs',async()=>{
 reset();await enqueueImageJob(query);await processImageJob(jobId,'test-key');
 const job=records.get(`vehicleImageJobs/${jobId}`);records.delete(`vehicleLibrary/${job.vehicleId}`);
 await enqueueImageJob(query);assert.equal(records.get(`vehicleImageJobs/${jobId}`).status,'needs_review');
});

test('exhausted API credits stop evaluation and give an actionable review reason',async()=>{
 reset();noCredits=true;await enqueueImageJob(query);await processImageJob(jobId,'test-key');
 const job=records.get(`vehicleImageJobs/${jobId}`);
 assert.equal(job.status,'needs_review');assert.match(job.reason,/credits exhausted/);assert.equal(aiCount,1);assert.equal(files.size,0);
});
test('image delivery updates saved vehicles without replacing the current vehicle or reviving deleted cards',async()=>{
 reset();
 const id='abc123';
 records.set('drivers/a',{vehicle:{...query,color:'White',imageUrl:'https://custom/current.jpg'},savedVehicles:{[id]:{...query,imageMatchTier:2}}});
 await enqueueImageJob(query,'a');await processImageJob(jobId,'test-key');
 await updateWaitingDrivers(jobId,records.get(`vehicleImageJobs/${jobId}`));
 const driver=records.get('drivers/a');
 assert.equal(driver.vehicle.imageUrl,'https://custom/current.jpg');
 assert.equal(driver.savedVehicles[id].imageMatchTier,1);
 assert.equal(driver.savedVehicles[id].libraryMatchedColor,query.color);
 records.set('drivers/b',{vehicle:{...query,color:'White'},savedVehicles:{}});
 await enqueueImageJob(query,'b');
 assert.deepEqual(records.get('drivers/b').savedVehicles,{});
});
