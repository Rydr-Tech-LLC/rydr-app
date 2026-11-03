const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),Module=require('node:module'),ts=require('typescript'),{createHash}=require('node:crypto');
const RealDate=Date;let now=RealDate.parse('2026-10-27T16:00:00Z');
global.Date=class extends RealDate {constructor(...args){super(...(args.length?args:[now]));}static now(){return now;}};
const docs=new Map();let serial=Promise.resolve(),workspace='live-beta',calls=[],failPublish=false,containerStatus='FINISHED',onDraft=null,draftHistory=[],failFacebook=false,onFacebook=null;
const hash=s=>createHash('sha256').update(s).digest('hex'),copy=x=>x==null?x:structuredClone(x);
function snap(path){return{id:path.split('/').at(-1),ref:doc(path),exists:docs.has(path),data:()=>copy(docs.get(path))};}
function merge(a,b){const out={...a};for(const [k,v]of Object.entries(b)){out[k]=v&&typeof v==='object'&&!Array.isArray(v)?merge(out[k]||{},v):v;}return out;}
function doc(path){return{path,id:path.split('/').at(-1),get:async()=>snap(path),collection:n=>col(`${path}/${n}`),set:async(d,o)=>docs.set(path,o?.merge?merge(docs.get(path)||{},copy(d)):copy(d)),update:async d=>{assert(docs.has(path));docs.set(path,{...docs.get(path),...copy(d)});}};}
function col(path,filters=[],max=Infinity){return{doc:i=>doc(`${path}/${i}`),add:async d=>{const r=doc(`${path}/${docs.size}`);await r.set(d);return r;},where:(k,o,v)=>col(path,[...filters,[k,o,v]],max),limit:n=>col(path,filters,n),orderBy:()=>col(path,filters,max),get:async()=>({docs:[...docs.keys()].filter(p=>p.startsWith(path+'/')&&!p.slice(path.length+1).includes('/')).filter(p=>filters.every(([k,o,v])=>o==='in'?v.includes(docs.get(p)[k]):docs.get(p)[k]===v)).slice(0,max).map(snap)})};}
const db={collection:col,runTransaction:callback=>{const result=serial.then(async()=>{let writing=false;const writes=[];const value=await callback({get:async ref=>{assert(!writing,'reads precede writes');return ref.get();},set:(r,d,o)=>{writing=true;writes.push(()=>r.set(d,o));},update:(r,d)=>{writing=true;writes.push(()=>r.update(d));},create:(r,d)=>{writing=true;writes.push(()=>{assert(!docs.has(r.path));return r.set(d);});}});for(const w of writes)await w();return value;});serial=result.catch(()=>{});return result;}};
class MetaRequestError extends Error {constructor(uncertain){super('Meta failed');this.uncertain=uncertain;}}
const original=Module._load;
Module._load=function(id,parent,...rest){
 if(id==='server-only')return{};
 if(parent?.filename.endsWith('socialAgent.ts')){
  if(id==='./firebaseAdmin')return{getWorkspaceDb:async()=>db};
  if(id==='./workspace')return{currentWorkspace:async()=>workspace};
  if(id==='./ai/socialCopy')return{socialCopy:async(_facts,_kind,_text,history)=>{draftHistory=history;if(onDraft)await onDraft();return{text:_kind==='post'?`Campus conversation ${now}`:'Hello, I’m Rowen, Rydr’s AI assistant. Interested in discussing a campus pilot?',visualBrief:'Campus community',handoff:false,reason:''};}};
  if(id==='./socialMeta')return{MetaRequestError,socialConnection:async()=>({pageId:'100',instagramId:'200'}),socialGraph:async(path,params,method)=>{calls.push({path,params,method});if(path.endsWith('/photos')){if(onFacebook)await onFacebook();if(failFacebook)throw new MetaRequestError(true);return{id:'500',post_id:'100_501'};}if(path.endsWith('/media_publish')){if(failPublish)throw new MetaRequestError(true);return{id:'400'};}if(path.endsWith('/media'))return{id:'300'};if(path==='300')return{status_code:containerStatus};if(path.endsWith('/messages'))return{message_id:'m'+calls.length};return{};}};
 }
 return original.call(this,id,parent,...rest);
};
require.extensions['.ts']=(mod,file)=>mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true}}).outputText,file);
const policy=require('../lib/socialPolicy.ts'),agent=require('../lib/socialAgent.ts');
const root='socialAgent/rowen',actor={uid:'admin',email:'admin@example.com'};
function inbound(mid='one',text='Can our student club discuss a pilot?',at=now,sender='123'){return{object:'instagram',entry:[{id:'200',messaging:[{sender:{id:sender},recipient:{id:'200'},timestamp:at,message:{mid,text}}]}]};}
function post(name='a'){docs.set(`${root}/posts/${name}`,{state:'queued',dueAt:now,caption:'Hello students',mediaUrl:'https://cdn.example.com/photo.jpg',mediaType:'image',aiGenerated:false,createdAt:now});}
beforeEach(()=>{docs.clear();calls=[];workspace='live-beta';now=RealDate.parse('2026-10-27T16:00:00Z');failPublish=false;failFacebook=false;onFacebook=null;containerStatus='FINISHED';onDraft=null;docs.set(root,{config:{active:true,facts:'Rydr seeks student clubs to discuss a Live Beta pilot.',endsAt:now+20*86400000,autoReplies:true,dailyPosts:2,dailyReplies:2}});docs.set(`${root}/metrics/latest`,{syncedAt:now});docs.set('metaConnections/rydr',{instagramId:'200',pageId:'100'});});
test('Eastern shift handles DST, weekends and campaign extension',()=>{assert(policy.socialOpen(docs.get(root).config));for(const time of ['2026-10-27T21:00:00Z','2026-10-31T16:00:00Z','2026-11-02T13:59:00Z'])assert(!policy.withinSendingHours(new Date(time)));assert(policy.withinSendingHours(new Date('2026-11-02T14:00:00Z')));assert(!policy.replyWindow(now-24*3600000));assert(!policy.replyWindow(now+1));assert(policy.replyWindow(now-1000));});
test('media URLs reject nonpublic and credential-bearing URLs; unavailable metrics remain null',()=>{for(const u of ['http://cdn.example.com/a.jpg','https://127.0.0.1/a','https://user:secret@example.com/a','https://x.internal/a'])assert.throws(()=>policy.publicMediaUrl(u));assert.equal(policy.metricValue({data:[]},'reach'),null);assert.equal(policy.metricValue({data:[{name:'reach',total_value:{value:0}}]},'reach'),0);});
test('concurrent runs publish once and keep a durable provider ID',async()=>{post();await Promise.all([agent.runSocialAgent(),agent.runSocialAgent()]);assert.equal(calls.filter(c=>c.path.endsWith('media_publish')).length,1);assert.equal(docs.get(`${root}/posts/a`).state,'published');assert.equal(docs.get(`${root}/posts/a`).mediaId,'400');});
test('uncertain publication is never automatically retried',async()=>{post();failPublish=true;await agent.runSocialAgent();assert.equal(docs.get(`${root}/posts/a`).state,'unknown');await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('media_publish')).length,1);});
test('processing containers reuse the same container and do not spend another daily slot',async()=>{post();containerStatus='IN_PROGRESS';await agent.runSocialAgent();now+=120000;containerStatus='FINISHED';await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/media')).length,1);assert.equal(docs.get(`${root}/days/2026-10-27`).postsReserved,1);assert.equal(docs.get(`${root}/posts/a`).state,'published');});
test('test workspace and off shift never call Meta writes',async()=>{post();workspace='test';await agent.runSocialAgent();assert.equal(calls.length,0);assert.equal(docs.get(`${root}/posts/a`).state,'simulated');workspace='live-beta';post('b');now=RealDate.parse('2026-10-27T21:00:00Z');assert((await agent.runSocialAgent()).skipped);assert.equal(calls.length,0);});
test('webhook retries deduplicate; wrong accounts and echoes never create conversations',async()=>{await agent.ingestSocialWebhook(inbound());await agent.ingestSocialWebhook(inbound());const wrong=inbound('wrong');wrong.entry[0].id='999';await agent.ingestSocialWebhook(wrong);const echo=inbound('echo');echo.entry[0].messaging[0].message.is_echo=true;await agent.ingestSocialWebhook(echo);assert.equal([...docs.keys()].filter(k=>k.includes('/messages/')).length,1);});
test('old opt-out events still stop a newer queued reply; deletions redact text',async()=>{await agent.ingestSocialWebhook(inbound('new'));await agent.ingestSocialWebhook(inbound('old','stop',now-1000));await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/messages')).length,0);assert(docs.get(`${root}/threads/${hash('123')}`).blocked);const deleted=inbound('new');deleted.entry[0].messaging[0].message.is_deleted=true;await agent.ingestSocialWebhook(deleted);assert.equal(docs.get(`${root}/threads/${hash('123')}/messages/${hash('new')}`).text,'[Deleted on Instagram]');});
test('replies obey review mode, message changes and the 24-hour window',async()=>{docs.get(root).config.autoReplies=false;await agent.ingestSocialWebhook(inbound());await agent.runSocialAgent();const tid=hash('123'),thread=docs.get(`${root}/threads/${tid}`);assert.equal(thread.state,'review');assert.equal(calls.length,0);await agent.reviewSocialReply({id:tid,lastInboundId:thread.lastInboundId,text:'Thanks for reaching out.'},actor);await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/messages')).length,1);await agent.ingestSocialWebhook(inbound('two','Hello again',now-25*3600000,'456'));await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/messages')).length,1);});
test('pausing or an opt-out during AI drafting prevents sending',async()=>{await agent.ingestSocialWebhook(inbound());onDraft=async()=>agent.pauseSocial();await agent.runSocialAgent();assert.equal(calls.length,0);assert.equal(docs.get(root).config.active,false);});
test('each new reply in a thread counts toward the daily cap',async()=>{docs.get(root).config.dailyReplies=1;await agent.ingestSocialWebhook(inbound());await agent.runSocialAgent();now+=1000;await agent.ingestSocialWebhook(inbound('two'));await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/messages')).length,1);});
test('post creation is idempotent and scheduling rejects weekends',async()=>{const input={operationId:'stable',caption:'Hello',mediaUrl:'https://cdn.example.com/photo.jpg',schedule:true,scheduledLocal:'2026-10-28T10:00'};await agent.saveSocialPost(input,actor);await agent.saveSocialPost(input,actor);assert.equal([...docs.keys()].filter(k=>k.includes('/posts/')).length,1);await assert.rejects(agent.saveSocialPost({...input,caption:'Changed'},actor));await assert.rejects(agent.saveSocialPost({...input,operationId:'other',scheduledLocal:'2026-10-31T10:00'},actor));});

test('ordinary support can receive a referral while safety and opt-outs stay held',async()=>{for(const text of ['I need a refund','My payment failed','How do I reset my password?','Can I talk to a person?'])assert.equal(policy.needsHuman(text),false);for(const text of ['I was injured','There is an emergency','Stop contacting me'])assert.equal(policy.needsHuman(text),true);await agent.ingestSocialWebhook(inbound('support','I need a refund'));assert.equal(docs.get(root+'/threads/'+hash('123')).state,'pending');await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/messages')).length,1);});
test('reply drafting receives prior conversation turns without deleted messages',async()=>{await agent.ingestSocialWebhook(inbound('first','What is Rydr?'));await agent.runSocialAgent();now+=1000;await agent.ingestSocialWebhook(inbound('second','How can my club join?'));await agent.runSocialAgent();assert(draftHistory.some(m=>m.direction==='outbound'));assert(draftHistory.some(m=>m.text==='What is Rydr?'));});


test('automatic content publishes at most once per shift, rotates graphics and shares the manual cap',async()=>{
 docs.get(root).config.autoPosts=true;
 await Promise.all([agent.runSocialAgent(),agent.runSocialAgent()]);
 await agent.runSocialAgent();
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
 const first=docs.get(root+'/posts/rowen-auto-2026-10-27');assert.equal(first.state,'published');
 post('manual');await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
 docs.delete(root+'/posts/manual');now+=86400000;await agent.runSocialAgent();
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,2);
 assert.notEqual(docs.get(root+'/posts/rowen-auto-2026-10-28').assetId,first.assetId);
});

test('automatic posts wait for email work and pending replies, and pause during drafting cancels publication',async()=>{
 docs.get(root).config.autoPosts=true;
 docs.set('marketingAgentCampaigns/student-beta-october-2026',{leaseUntil:now+60000});
 await agent.runSocialAgent();assert.equal([...docs.keys()].filter(k=>k.includes('/posts/')).length,0);
 docs.delete('marketingAgentCampaigns/student-beta-october-2026');
 for(let i=0;i<4;i++)await agent.ingestSocialWebhook(inbound('in'+i,'Hello',now,String(1000+i)));
 await agent.runSocialAgent();assert.equal([...docs.keys()].filter(k=>k.includes('/posts/')).length,0);
 for(const key of [...docs.keys()])if(key.includes('/threads/'))docs.delete(key);
 onDraft=async()=>agent.pauseSocial();await agent.runSocialAgent();
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,0);
 assert.equal(docs.get(root+'/posts/rowen-auto-2026-10-27').state,'cancelled');
});

test('stale or disabled automatic content never publishes later',async()=>{
 docs.get(root).config.autoPosts=true;post('old');
 Object.assign(docs.get(root+'/posts/old'),{automatic:true,autoDay:'2026-10-26'});
 await agent.runSocialAgent();assert.equal(docs.get(root+'/posts/old').state,'cancelled');
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
 now+=86400000;post('disabled');Object.assign(docs.get(root+'/posts/disabled'),{automatic:true,autoDay:'2026-10-28'});
 docs.get(root).config.autoPosts=false;await agent.runSocialAgent();
 assert.equal(docs.get(root+'/posts/disabled').state,'cancelled');
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
});

test('automatic content in Test is simulated and never contacts Meta',async()=>{
 workspace='test';docs.get(root).config.autoPosts=true;await agent.runSocialAgent();
 assert.equal(docs.get(root+'/posts/rowen-auto-2026-10-27').state,'simulated');assert.equal(calls.length,0);
});


test('one automatic content slot publishes once per platform across concurrent runs',async()=>{
 Object.assign(docs.get(root).config,{autoPosts:true,facebookPosts:true});
 await Promise.all([agent.runSocialAgent(),agent.runSocialAgent()]); await agent.runSocialAgent();
 assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,1);
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
 const item=docs.get(root+'/posts/rowen-auto-2026-10-27');assert.equal(item.facebook.state,'published');assert.equal(item.state,'published');
 assert.equal(docs.get(root+'/days/2026-10-27').postsReserved,1);
 assert.equal(docs.get(root+'/days/2026-10-27').facebookPosts,1);
});
test('Facebook uncertainty preserves Instagram success and is never automatically retried',async()=>{
 Object.assign(docs.get(root).config,{autoPosts:true,facebookPosts:true});failFacebook=true;
 await agent.runSocialAgent(); await agent.runSocialAgent();
 const item=docs.get(root+'/posts/rowen-auto-2026-10-27');assert.equal(item.state,'published');assert.equal(item.facebook.state,'unknown');
 assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,1);
 await agent.changeSocialPost({id:'rowen-auto-2026-10-27',action:'resolveFacebook'});
 assert.equal(docs.get(root+'/posts/rowen-auto-2026-10-27').facebook.state,'resolved');
});
test('Instagram uncertainty does not block an independently recorded Facebook delivery',async()=>{
 Object.assign(docs.get(root).config,{autoPosts:true,facebookPosts:true});failPublish=true;
 await agent.runSocialAgent();await agent.runSocialAgent();
 const item=docs.get(root+'/posts/rowen-auto-2026-10-27');assert.equal(item.state,'unknown');assert.equal(item.facebook.state,'published');
 assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,1);
});
test('container polling reuses the Facebook delivery and daily slot',async()=>{
 Object.assign(docs.get(root).config,{autoPosts:true,facebookPosts:true});containerStatus='IN_PROGRESS';
 await agent.runSocialAgent();now+=120000;containerStatus='FINISHED';await agent.runSocialAgent();
 assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,1);
 assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
 assert.equal(docs.get(root+'/days/2026-10-27').postsReserved,1);
});
test('Facebook opt-out, shift boundary and Test cannot write to the Page',async()=>{
 Object.assign(docs.get(root).config,{autoPosts:true,facebookPosts:true});workspace='test';await agent.runSocialAgent();assert.equal(calls.length,0);
 assert.equal(docs.get(root+'/posts/rowen-auto-2026-10-27').facebook.state,'simulated');
 workspace='live-beta';now+=86400000;docs.get(root).config.facebookPosts=false;await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,0);
 now=RealDate.parse('2026-10-29T21:00:00Z');docs.get(root).config.facebookPosts=true;await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,0);
});


test('an interrupted unattempted Facebook sibling resumes only in its original shift',async()=>{
 Object.assign(docs.get(root).config,{autoPosts:true,facebookPosts:true});
 post('interrupted');Object.assign(docs.get(root+'/posts/interrupted'),{state:'published',automatic:true,facebookTarget:true,autoDay:'2026-10-27',reservedDay:'2026-10-27',publishedAt:now});
 docs.set(root+'/days/2026-10-27',{postsReserved:1});
 await agent.runSocialAgent();await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,1);
 post('old');Object.assign(docs.get(root+'/posts/old'),{state:'published',facebookTarget:true,autoDay:'2026-10-26',reservedDay:'2026-10-26'});
 await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/photos')).length,1);
});

test('failed AI preparation can retry after cooldown without repeating a Meta attempt',async()=>{
 docs.get(root).config.autoPosts=true;
 onDraft=async()=>{throw new Error('API quota exhausted');};await agent.runSocialAgent();
 const p=root+'/posts/rowen-auto-2026-10-27';assert.equal(docs.get(p).state,'failed');
 onDraft=null;await agent.runSocialAgent();assert.equal(calls.length,0);
 now+=61*60000;await agent.runSocialAgent();assert.equal(docs.get(p).state,'published');
 await agent.runSocialAgent();assert.equal(calls.filter(c=>c.path.endsWith('/media_publish')).length,1);
});

test('failed automatic preparation never retries reserved or attempted posts',async()=>{
 docs.get(root).config.autoPosts=true;
 const p=root+'/posts/rowen-auto-2026-10-27';
 for(const extra of [{reservedDay:'2026-10-27'},{processingAt:now-3600000},{facebook:{state:'unknown'}},{draftAttempts:3}]){
 docs.set(p,{state:'failed',automatic:true,autoDay:'2026-10-27',caption:'Preparing today’s caption…',updatedAt:now-3600000,...extra});
 await agent.runSocialAgent();assert.equal(calls.length,0);
 }
});

