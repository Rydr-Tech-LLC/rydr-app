const {test}=require('node:test');
const assert=require('node:assert/strict');
const {phoneHash}=require('../firebase/functions/src/services/liveBetaAccessPolicy');
const {accountWorkspace,workspaceDefinition,workspaceServiceURL}=require('../firebase/functions/src/services/workspacePolicy');
const {runInWorkspace,currentWorkspace}=require('../firebase/functions/src/services/workspaceRuntime');
const policy={configured:true,blockedAuthUids:['test-uid'],blockedPhoneHashes:[phoneHash('+15555550101')]};
test('canonical test identity stays in Test; real identity uses separate live database',()=>{
 assert.equal(accountWorkspace('test-uid','+15555550999',policy),'test');
 assert.equal(accountWorkspace('recreated','+15555550101',policy),'test');
 assert.equal(accountWorkspace('real','+15555550999',policy),'live-beta');
 assert.equal(workspaceDefinition('test').stripeMode,'test');
 assert.equal(workspaceDefinition('live-beta').databaseId,'live-beta');
 assert.throws(()=>accountWorkspace('real','',null),/policy_unavailable/);
 assert.throws(()=>workspaceDefinition('__proto__'),/invalid_workspace/);
});
test('concurrent asynchronous requests cannot leak workspace context',async()=>{
 const outcomes=await Promise.all(Array.from({length:40},(_,i)=>runInWorkspace(i%2?'test':'live-beta',async()=>{
 const initial=currentWorkspace();await new Promise(resolve=>setTimeout(resolve,Math.random()*15));assert.equal(currentWorkspace(),initial);return currentWorkspace();
 })));
 assert.equal(outcomes.filter(v=>v==='test').length,20);assert.equal(currentWorkspace(),'test');
});
test('service routing replaces previous workspace and preserves route isolation',()=>{
 assert.equal(workspaceServiceURL('https://example.com/workspaces/test/','live-beta'),'https://example.com/workspaces/live-beta');
 assert.throws(()=>workspaceServiceURL('https://example.com','live'),/invalid_workspace/);
});

test('backend authenticates canonical Auth phone and rejects cross-workspace requests',async()=>{
 const configPath=require.resolve('../src/config/firebase');let user={uid:'real',phoneNumber:'+15555550999'};
 const authPath=require.resolve('../firebase/functions/src/services/firebaseWorkspace');const previousAuth=require.cache[authPath];require.cache[authPath]={id:authPath,filename:authPath,loaded:true,exports:{configureWorkspaceSDK:()=>{},verifyWorkspaceToken:async()=>({decoded:{uid:user.uid,aud:'rydrapp-c7ec1'},user,staff:false})}};
 const previous=require.cache[configPath];require.cache[configPath]={id:configPath,filename:configPath,loaded:true,exports:{initializeFirebase:()=>({app:{}}),getControlFirestore:()=>({collection:()=>({doc:()=>({get:async()=>({data:()=>policy})})})}),admin:{auth:()=>({verifyIdToken:async(_token,revoked)=>{assert.equal(revoked,true);return{uid:user.uid,phone_number:'+15555550999'}},getUser:async()=>user})}}};
 try{const {requireFirebaseAuth}=require('../src/middleware/firebaseAuth');async function invoke(workspace){let next=false;const res={statusCode:200,status(n){this.statusCode=n;return this},json(body){this.body=body;return this}};await runInWorkspace(workspace,()=>requireFirebaseAuth({header:()=> 'Bearer token'},res,()=>{next=true}));return{res,next}}
 assert.equal((await invoke('live-beta')).next,true);assert.equal((await invoke('test')).res.statusCode,403);
 user={uid:'real',phoneNumber:'+15555550101'};assert.equal((await invoke('live-beta')).res.statusCode,403,'current test phone overrides stale ID-token phone');assert.equal((await invoke('test')).next,true);
 user={uid:'real',disabled:true};assert.equal((await invoke('live-beta')).res.statusCode,403);
 }finally{if(previousAuth)require.cache[authPath]=previousAuth;else delete require.cache[authPath];if(previous)require.cache[configPath]=previous;else delete require.cache[configPath]}
});

test('real HTTP JSON requests preserve workspace through middleware and concurrent handlers',async()=>{
 const express=require('express');const {workspaceRouting}=require('../src/services/workspaceContext');const app=express();app.use(workspaceRouting);app.use(express.json());app.post('/echo',async(req,res)=>{await new Promise(resolve=>setTimeout(resolve,Math.random()*15));res.json({workspace:currentWorkspace(),value:req.body.value})});const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));const base=`http://127.0.0.1:${server.address().port}`;
 try{await Promise.all(Array.from({length:24},async(_,i)=>{const workspace=i%2?'test':'live-beta';const r=await fetch(base+'/workspaces/'+workspace+'/echo',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({value:i})});assert.equal(r.status,200);assert.deepEqual(await r.json(),{workspace,value:i})}));assert.equal((await fetch(base+'/workspaces/__proto__/echo',{method:'POST'})).status,404);const legacy=await fetch(base+'/echo',{method:'POST',headers:{'content-type':'application/json'},body:'{"value":"legacy"}'});assert.deepEqual(await legacy.json(),{workspace:'test',value:'legacy'});}finally{await new Promise(resolve=>server.close(resolve))}
});
