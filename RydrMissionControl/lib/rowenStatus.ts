import 'server-only';
import { getWorkspaceDb } from './firebaseAdmin';
import { rowenShift } from './rowenShift';
import { easternDay } from './marketingAgentPolicy';
export async function rowenStatus() {
 const db=await getWorkspaceDb(), now=Date.now(), shift=rowenShift(new Date(now));
 const [emailDoc,socialDoc,failed]=await Promise.all([db.collection('marketingAgentCampaigns').doc('student-beta-october-2026').get(),db.collection('socialAgent').doc('rowen').get(),db.collection('socialAgent').doc('rowen').collection('posts').where('state','in',['failed','unknown']).limit(50).get()]);
 const email=emailDoc.data(), social=socialDoc.data();
 const emailActive=email?.status==='active'&&Date.parse(email.endsAt)>now, socialActive=social?.config?.active&&social.config.endsAt>now;
 const tasks=[];
 if(emailActive&&email?.leaseUntil>now)tasks.push({label:'Live Beta Marketing',detail:email.activity||'Processing outreach'});
 if(socialActive&&social?.leaseUntil>now)tasks.push({label:'Social Media',detail:social.activity||'Processing social content and replies'});
 const issues=[email?.lastError,social?.lastError,...failed.docs.filter(d=>d.data().autoDay===easternDay()).map(d=>d.data().error)].filter(Boolean);
 const schedulerAt=Math.max(email?.schedulerLastSeen||0,social?.schedulerLastSeen||0);
 const stale=shift.canWork&&(emailActive||socialActive)&&schedulerAt<now-30*60000;
 if(stale)issues.push('No cloud scheduler check in the last 30 minutes.');
 let label='Waiting for next task',detail='On shift. Checking the queue between batches.',tone='ready';
 if(!emailActive&&!socialActive){label='Paused';detail='No active campaign.';tone='paused';}
 else if(!shift.onShift){label='Off shift';detail='Returns on the next weekday at 9 a.m. Eastern.';tone='paused';}
 else if(shift.resume){label=shift.label;detail=`New work resumes at ${shift.resume} Eastern. A send already in progress may finish.`;tone='break';}
 else if(tasks.length){label=`Working · ${tasks.map(t=>t.label).join(' + ')}`;detail=tasks.map(t=>t.detail).join(' · ');tone='working';}
 else if(issues.length){label='Needs attention';detail=String(issues[0]);tone='warning';}
 else if(shift.label==='Ending Shift'){label='Ending Shift';detail='Finishing eligible work before 5 p.m. Eastern.';}
 return {label,detail,tone,issues:[...new Set(issues)].slice(0,3),tasks,schedulerAt: schedulerAt||null,checkedAt:now,breaks:'Breaks 10:45–11 a.m. and 3–3:15 p.m. · Lunch 12:30–1 p.m. Eastern'};
}
