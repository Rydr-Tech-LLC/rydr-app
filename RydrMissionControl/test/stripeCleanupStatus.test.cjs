const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),ts=require('typescript');
require.extensions['.ts']=(mod,file)=>mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,file);
const {stripeCleanupStatus}=require('../lib/stripeCleanupStatus.ts');
test('read-only probe requires authentication in both workspaces without a user identifier',async()=>{
 const oldFetch=global.fetch,oldBase=process.env.STRIPE_BACKEND_BASE_URL,oldSecret=process.env.RYDR_INTERNAL_ADMIN_SECRET;
 try{
 process.env.STRIPE_BACKEND_BASE_URL='https://backend.example';process.env.RYDR_INTERNAL_ADMIN_SECRET='test-only';
 const calls=[];global.fetch=async(url,options)=>{calls.push({url,body:JSON.parse(options.body)});return {status:400,json:async()=>({error:'invalid_account'})};};
 const good=await stripeCleanupStatus('admin');assert.equal(good.configured,true);assert.equal(calls.length,2);assert.ok(calls.every(x=>!x.body.uid&&x.body.role==='configuration_check'));assert.ok(calls[1].url.includes('/live-beta/'));
 global.fetch=async()=>({status:401,json:async()=>({error:'unauthorized'})});assert.equal((await stripeCleanupStatus('admin')).configured,false);
 delete process.env.RYDR_INTERNAL_ADMIN_SECRET;assert.equal((await stripeCleanupStatus('admin')).reason,'missing_configuration');
 }finally{global.fetch=oldFetch;for(const [key,value]of Object.entries({STRIPE_BACKEND_BASE_URL:oldBase,RYDR_INTERNAL_ADMIN_SECRET:oldSecret})){if(value===undefined)delete process.env[key];else process.env[key]=value;}}
});
