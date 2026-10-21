const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');

function fixture(authenticated = true) {
  const updates = [], audits = [], reads = [];
  const mocks = {
    'next/server': {NextResponse: {json: (body, options = {}) => ({body, status: options.status || 200})}},
    'firebase-admin/firestore': {FieldValue: {serverTimestamp: () => 'timestamp', delete: () => 'delete'}, Timestamp: {}},
    '@/lib/session': {getAdminSession: async () => authenticated ? {uid: 'staff'} : null},
    '@/lib/firebaseAdmin': {getWorkspaceDb: async () => ({collection: name => ({doc: uid => ({
      get: async () => {reads.push([name,uid]); return {exists:true,data:()=>({driverSex:'male'})};},
      set: async (update, options) => updates.push({update,options})
    })})}),getWorkspaceAuth:async()=>{throw Error('Sex disclosure must not change Firebase Auth');}},
    '@/lib/auditLog': {writeAuditLog: async value => audits.push(value)}
  };
  const source = fs.readFileSync(require('node:path').join(__dirname,'../app/api/drivers/[uid]/profile/route.ts'),'utf8');
  const compiled = ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const exports = {};
  new Function('require','exports',compiled)(name=>{assert.ok(mocks[name],name);return mocks[name];},exports);
  return {updates,audits,reads,patch:body=>exports.PATCH({json:async()=>body},{params:Promise.resolve({uid:'driver'})})};
}

test('driver disclosure updates are validated, workspace scoped, and audited',async()=>{
  for(const driverSex of ['female','male','undisclosed']) {
    const f=fixture();assert.equal((await f.patch({driverSex})).status,200);
    assert.deepEqual(f.reads,[['drivers','driver']]);
    assert.equal(f.updates[0].update.driverSex,driverSex);
    assert.equal(f.updates[0].options.merge,true);
    assert.equal(f.audits[0].targetId,'driver');
    assert.ok(f.audits[0].metadata.fields.includes('driverSex'));
  }
});
test('invalid sex disclosures never mutate profiles',async()=>{
  for(const driverSex of ['Female','',null,42,{},'genderIdentity']) {
    const f=fixture();assert.equal((await f.patch({driverSex})).status,400);assert.equal(f.updates.length,0);
  }
});
test('omitted disclosure is preserved rather than reset',async()=>{
  const f=fixture();assert.equal((await f.patch({})).status,200);
  assert.equal(Object.hasOwn(f.updates[0].update,'driverSex'),false);
});
test('unauthenticated disclosure edits are denied before profile reads',async()=>{
  const f=fixture(false);assert.equal((await f.patch({driverSex:'female'})).status,401);
  assert.deepEqual(f.reads,[]);assert.deepEqual(f.updates,[]);
});
