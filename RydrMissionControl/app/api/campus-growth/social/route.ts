import { NextRequest, NextResponse } from 'next/server';
import { getAdminSession } from '@/lib/session';
import { changeSocialPost, draftSocialPost, pauseSocial, reviewSocialReply, saveSocialConfig, saveSocialPost, socialMessages, socialSnapshot, subscribeSocialInbox, syncSocialAnalytics } from '@/lib/socialAgent';
import { currentWorkspace } from '@/lib/workspace';
export const runtime = 'nodejs';
export const maxDuration = 120;
const json = (data: unknown, status = 200) => NextResponse.json(data,{status,headers:{'Cache-Control':'no-store'}});
export async function GET(request: NextRequest) {
  if (!await getAdminSession()) return json({error:'Administrator access required.'},401);
  try { const thread = request.nextUrl.searchParams.get('thread'); return json(thread ? {messages:await socialMessages(thread)} : await socialSnapshot()); }
  catch { return json({error:'Could not load social workflows. Check the database connection.'},503); }
}
export async function POST(request: NextRequest) {
  const actor = await getAdminSession(); if (!actor) return json({error:'Administrator access required.'},401);
  if (request.headers.get('origin') !== request.nextUrl.origin) return json({error:'Invalid request origin.'},403);
  try {
    const raw = await request.text(); if (raw.length > 20000) return json({error:'Request too large.'},413);
    const input = JSON.parse(raw);
    switch(input.action) {
      case 'config': await saveSocialConfig(input,actor); break;
      case 'pause': await pauseSocial(); break;
      case 'draft': return json(await draftSocialPost(input.topic));
      case 'savePost': return json(await saveSocialPost(input,actor));
      case 'schedule': case 'cancel': case 'resolve': await changeSocialPost(input); break;
      case 'reply': case 'handoff': case 'resolveReply': await reviewSocialReply(input,actor); break;
      case 'subscribe': if (await currentWorkspace() !== 'live-beta') throw new Error('Connect the live inbox in Live Beta.'); await subscribeSocialInbox(); break;
      case 'analytics': if (await currentWorkspace() !== 'live-beta') throw new Error('Live analytics are available in Live Beta.'); return json(await syncSocialAnalytics());
      default: return json({error:'Unknown action.'},400);
    }
    return json({ok:true});
  } catch(error) { return json({error:error instanceof Error ? error.message : 'Social workflow action failed.'},400); }
}
