const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
const {createHmac} = require('node:crypto');
require.extensions['.ts'] = (mod, filename) => mod._compile(ts.transpileModule(fs.readFileSync(filename,'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true}}).outputText, filename);
const security = require('../lib/metaSecurity.ts');
const key = 'ab'.repeat(32), state = '12'.repeat(32);
test('OAuth state binds the callback to the admin, browser and time window', () => {
  const saved = {uid:'admin',expiresAt:1001,used:false};
  assert(security.validMetaState(saved,'admin',state,state,1000));
  assert(!security.validMetaState(saved,'other',state,state,1000));
  assert(!security.validMetaState(saved,'admin',state,'34'.repeat(32),1000));
  assert(!security.validMetaState(saved,'admin',state,state,1001));
  assert(!security.validMetaState({...saved,used:true},'admin',state,state,1000));
  assert(!security.validMetaState(undefined,'admin',state,state,1000));
});
test('encrypted tokens cannot cross workspaces or be tampered with', () => {
  const token = 'test-token-not-a-real-credential';
  const encrypted = security.encryptMetaToken(token,key,'test:page');
  assert(!encrypted.includes(token));
  assert.equal(security.decryptMetaToken(encrypted,key,'test:page'),token);
  assert.throws(()=>security.decryptMetaToken(encrypted,key,'live-beta:page'));
  assert.throws(()=>security.decryptMetaToken(encrypted,'cd'.repeat(32),'test:page'));
  const parts = encrypted.split('.'); parts[2] = Buffer.from('tampered').toString('base64url');
  assert.throws(()=>security.decryptMetaToken(parts.join('.'),key,'test:page'));
  assert.throws(()=>security.encryptMetaToken(token,'short','test:page'));
});
test('webhooks require exact raw-body HMAC with the app secret', () => {
  const body = '{"object":"instagram","entry":[]}';
  const signature = 'sha256='+createHmac('sha256','test-secret').update(body).digest('hex');
  assert(security.validMetaSignature(body,signature,'test-secret'));
  assert(!security.validMetaSignature(body+' ',signature,'test-secret'));
  assert(!security.validMetaSignature(body,signature,'other-secret'));
  assert(!security.validMetaSignature(body,'','test-secret'));
  assert(!security.validMetaSignature(body,signature,''));
});
test('redirect origin rejects credentials, HTTP, paths and query parameters', () => {
  assert.equal(security.metaOrigin('https://rydr-app-missioncontrol.vercel.app'),'https://rydr-app-missioncontrol.vercel.app');
  for (const value of ['http://example.com','https://example.com/callback','https://example.com?redirect=evil','https://user:password@example.com','https://example.com#fragment']) assert.throws(()=>security.metaOrigin(value));
});

const Module = require('node:module');
const records = new Map();
let providerCalls = 0, fakePageId = '1444445918742638';
const ref = path => ({get:async()=>({data:()=>records.get(path)}),set:async value=>records.set(path,value),update:async value=>records.set(path,{...records.get(path),...value})});
const db = {collection:name=>({doc:id=>ref(`${name}/${id}`)}),runTransaction:async fn=>fn({get:r=>r.get(),update:(r,v)=>r.update(v)})};
const originalLoad = Module._load;
Module._load = function(id,parent,...rest) {
  if(id==='server-only') return {};
  if(parent?.filename.endsWith('metaConnection.ts') && id==='./firebaseAdmin') return {getWorkspaceDb:async()=>db};
  if(parent?.filename.endsWith('metaConnection.ts') && id==='./workspace') return {currentWorkspace:async()=>'test'};
  return originalLoad.call(this,id,parent,...rest);
};
const connection = require('../lib/metaConnection.ts');
Object.assign(process.env,{META_APP_SECRET:'test-secret',META_TOKEN_ENCRYPTION_KEY:key,META_WEBHOOK_VERIFY_TOKEN:'test-verify',META_PUBLIC_ORIGIN:'https://mc.example.com'});
const originalFetch = global.fetch;
test('OAuth callback validates identity, consumes state once, encrypts tokens and exposes only metadata', async () => {
  global.fetch = async url => {
    providerCalls++;
    return {ok:true,json:async()=>String(url).includes('oauth/access_token') ? {access_token:'private-user-token',expires_in:3600} : {data:[{id:fakePageId,name:'Rydr Tech',access_token:'private-page-token',instagram_business_account:{id:'ig-1',username:'rydr_tech'}}]}};
  };
  try {
    const login = await connection.startMetaLogin('admin');
    assert.equal(new URL(login.url).searchParams.get('redirect_uri'),'https://mc.example.com/api/meta/test/callback');
    assert(!JSON.stringify([...records.values()]).includes(login.state));
    await assert.rejects(connection.finishMetaLogin('other',login.state,login.state,'code'),/verified/);
    assert.equal(providerCalls,0);
    await connection.finishMetaLogin('admin',login.state,login.state,'code');
    const saved = records.get('metaConnections/rydr');
    assert.equal(security.decryptMetaToken(saved.tokenEncrypted,key,'test:1444445918742638'),'private-page-token');
    assert(!JSON.stringify([...records.values()]).includes('private-page-token'));
    const status = await connection.metaStatus(); assert.equal(status.connected,true); assert(!JSON.stringify(status).includes('tokenEncrypted'));
    await assert.rejects(connection.finishMetaLogin('admin',login.state,login.state,'code'),/verified/);
    assert.equal(providerCalls,2);
    const old = JSON.stringify(saved); fakePageId = 'unrelated-page';
    const second = await connection.startMetaLogin('admin');
    await assert.rejects(connection.finishMetaLogin('admin',second.state,second.state,'code'),/Select Rydr/);
    assert.equal(JSON.stringify(records.get('metaConnections/rydr')),old);
    await connection.recordMetaWebhook({object:'instagram',entry:[{id:'unrelated',messaging:[{text:'private-message'}]}]});
    assert.equal(records.get('metaConnections/rydr').lastWebhookAt,null);
    await connection.recordMetaWebhook({object:'instagram',entry:[{id:'ig-1',messaging:[{text:'private-message'}]}]});
    assert(records.get('metaConnections/rydr').lastWebhookAt > 0);
    assert(!JSON.stringify([...records.values()]).includes('private-message'));
  } finally {global.fetch=originalFetch;}
});
