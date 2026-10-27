const origin = process.env.MARKETING_AGENT_PUBLIC_URL;
const secret = process.env.SOCIAL_AGENT_RUN_SECRET || process.env.MARKETING_AGENT_RUN_SECRET;
if (!origin || new URL(origin).protocol !== 'https:' || !secret) throw new Error('Configure the social scheduler URL and secret.');
const response = await fetch(new URL('/api/campus-growth/social/run',origin),{method:'POST',redirect:'error',signal:AbortSignal.timeout(295000),headers:{Authorization:`Bearer ${secret}`,'x-rydr-workspace':'live-beta','Content-Type':'application/json'},body:'{}'});
if (!response.ok) throw new Error(`Social run failed (${response.status}); inspect Mission Control activity.`);
const result = await response.json(); console.log(JSON.stringify({ok:result.ok ?? false,skipped:result.skipped ?? false}));
