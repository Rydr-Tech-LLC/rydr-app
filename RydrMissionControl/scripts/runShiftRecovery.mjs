import { setTimeout as delay } from 'node:timers/promises';
const day = process.env.RECOVERY_DAY;
if (!/^\d{4}-\d{2}-\d{2}$/.test(day || '')) throw new Error('Set an explicit recovery date.');
const origin = process.env.MARKETING_AGENT_PUBLIC_URL;
if (!origin || new URL(origin).protocol !== 'https:') throw new Error('Missing HTTPS worker origin.');
const started = Date.now();
function eastern() {
 const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'America/New_York',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date()).map(p=>[p.type,p.value]));
 return {day:`${p.year}-${p.month}-${p.day}`,minute:Number(p.hour)*60+Number(p.minute)};
}
while (Date.now()-started < 5*3600000) {
 const clock=eastern();
 if (clock.day !== day || clock.minute >= 17*60+50) break;
 if (clock.minute >= 9*60) {
  for (const [name,path,key] of [['email','agent','MARKETING_AGENT_RUN_SECRET'],['social','social','SOCIAL_AGENT_RUN_SECRET']]) {
   if(name==='social' && clock.minute>=17*60)continue;
   try {
    if(!process.env[key])throw new Error('Missing scheduler credential');
    const r=await fetch(new URL(`/api/campus-growth/${path}/run`,origin),{method:'POST',redirect:'error',signal:AbortSignal.timeout(295000),headers:{Authorization:`Bearer ${process.env[key]}`,'x-rydr-workspace':'live-beta','Content-Type':'application/json'},body:'{}'});
    const result=await r.json();
    console.log(JSON.stringify({at:new Date().toISOString(),worker:name,http:r.status,ok:r.ok&&!result.error,skipped:!!result.skipped,sent:result.sent??0}));
   } catch { console.log(JSON.stringify({at:new Date().toISOString(),worker:name,ok:false,error:'Worker request failed; inspect Mission Control.'})); }
  }
 }
 await delay(15*60*1000);
}
console.log('Recovery segment finished.');
