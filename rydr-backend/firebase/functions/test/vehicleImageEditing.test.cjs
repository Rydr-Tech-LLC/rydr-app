const test=require('node:test');const assert=require('node:assert/strict');
const {buildVehicleEditPrompt,editVehicleBackground}=require('../lib/services/vehicleImageEditing');
test('background edits retain vehicle constraints and use image-edit input rather than creating a replacement vehicle',async()=>{
 assert.match(buildVehicleEditPrompt('white background'),/Preserve the exact vehicle/);
 const previous=global.fetch;
 try{global.fetch=async(url,options)=>{assert.equal(url,'https://api.openai.com/v1/images/edits');assert.equal(options.body.get('image[]').size,4);assert.equal(options.body.get('image[]').name,'vehicle.jpg');assert.match(options.body.get('prompt'),/Do not recolor/);return{ok:true,json:async()=>({data:[{b64_json:Buffer.from([255,216,255,0]).toString('base64')}]})};};const image=await editVehicleBackground({data:Buffer.from([255,216,255,0]),contentType:'image/jpeg'},'fixture');assert.equal(image.contentType,'image/jpeg');}
 finally{global.fetch=previous;}
});
test('quota failures are actionable and invalid source images are rejected before API calls',async()=>{
 await assert.rejects(editVehicleBackground({data:Buffer.from('bad'),contentType:'image/svg+xml'},'fixture'),/JPEG/);
 const previous=global.fetch;
 try{global.fetch=async()=>({ok:false,status:429,json:async()=>({error:{code:'insufficient_quota'}})});await assert.rejects(editVehicleBackground({data:Buffer.from([255,216]),contentType:'image/jpeg'},'fixture'),/credits/);}
 finally{global.fetch=previous;}
});
