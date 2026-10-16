const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), ts = require('typescript');
require.extensions['.ts'] = (mod, file) => mod._compile(ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, file);
const { preserveAccountVehicleHistory } = require('../lib/accountVehicleArchive.ts');
function fixture(fail = false) {
 const writes = [];
 const archive = { collection: name => ({ doc: id => ({ set: async data => { if (fail) throw Error('archive unavailable'); writes.push({name,id,data}); } }) }), set: async data => writes.push({metadata:data}) };
 const ref = { id:'driver', firestore:{ collection:name => { assert.equal(name,'accountVehicleArchives');return {doc:uid=>{assert.equal(uid,'driver');return archive;}};} }, collection: name => {assert.equal(name,'vehicleArchive'); return { get:async()=>({docs:[{id:'old',data:()=>({vehicle:{plate:'OLD'}})}]})};} };
 return {ref,writes};
}
test('vehicle and plate history survives outside the deleted profile', async()=>{
 const {ref,writes}=fixture();await preserveAccountVehicleHistory(ref,{vehicle:{vin:'CURRENT',plate:'NOW'},savedVehicles:{second:{plate:'SAVED'}}},'admin','request');
 assert.deepEqual(writes.slice(0,3).map(x=>x.id),['history_old','current','saved_second']);assert.equal(writes[1].data.vehicle.plate,'NOW');assert.equal(writes[3].metadata.vehicleRecordCount,3);
});
test('archive errors propagate before account removal can continue',async()=>{
 const {ref,writes}=fixture(true);await assert.rejects(preserveAccountVehicleHistory(ref,{},'admin','request'),/archive unavailable/);assert.equal(writes.length,0);
});
