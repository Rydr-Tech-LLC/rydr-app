const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),ts=require('typescript'),Module=require('node:module');
let workspace='live-beta';
const file=require('node:path').resolve(__dirname,'../lib/stripeCleanup.ts');
const mod=new Module(file,module);mod.filename=file;mod.paths=module.paths;
mod.require=id=>id==='@/lib/workspace'?{currentWorkspace:async()=>workspace,workspaceServiceURL:async base=>`${base}/workspaces/${workspace}`} : require(id);
mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,file);
const {cleanupStripeAccount}=mod.exports;
test('cleanup uses workspace Stripe records and forwards useful backend failures',async()=>{
 const originalFetch=global.fetch,base=process.env.STRIPE_BACKEND_BASE_URL,secret=process.env.RYDR_INTERNAL_ADMIN_SECRET;
 try{
 process.env.STRIPE_BACKEND_BASE_URL='https://backend.example';process.env.RYDR_INTERNAL_ADMIN_SECRET='unit-test';
 const calls=[];global.fetch=async(url,options)=>{calls.push({url,body:JSON.parse(options.body)});return {ok:true,json:async()=>({ok:true})};};
 await cleanupStripeAccount('driver',{stripeMode:'test',stripeAccountId:'acct_test',stripeProfiles:{live:{stripeAccountId:'acct_live'}}},'admin','request','driver');
 assert.equal(calls[0].url,'https://backend.example/workspaces/live-beta/admin/cleanup-account');assert.equal(calls[0].body.stripeAccountId,'acct_live');
 assert.deepEqual(await cleanupStripeAccount('driver',{stripeMode:'test',stripeAccountId:'acct_test'},'admin','request','driver'),{notRequired:true});assert.equal(calls.length,1);
 global.fetch=async()=>({ok:false,json:async()=>({error:'cleanup_failed',detail:'Settle pending payouts'})});
 await assert.rejects(cleanupStripeAccount('driver',{stripeMode:'live',stripeAccountId:'acct_live'},'admin','request','driver'),/Settle pending payouts/);
 delete process.env.RYDR_INTERNAL_ADMIN_SECRET;
 await assert.rejects(cleanupStripeAccount('driver',{stripeMode:'live',stripeAccountId:'acct_live'},'admin','request','driver'),/not configured/);
 }finally{global.fetch=originalFetch;if(base===undefined)delete process.env.STRIPE_BACKEND_BASE_URL;else process.env.STRIPE_BACKEND_BASE_URL=base;if(secret===undefined)delete process.env.RYDR_INTERNAL_ADMIN_SECRET;else process.env.RYDR_INTERNAL_ADMIN_SECRET=secret;}
});
