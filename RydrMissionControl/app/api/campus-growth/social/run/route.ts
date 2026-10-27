import { NextRequest, NextResponse } from 'next/server';
import { constantEqual } from '@/lib/metaSecurity';
import { getAdminSession } from '@/lib/session';
import { runSocialAgent } from '@/lib/socialAgent';
export const runtime = 'nodejs';
export const maxDuration = 300;
export async function POST(request: NextRequest) {
  const secret = process.env.SOCIAL_AGENT_RUN_SECRET || process.env.MARKETING_AGENT_RUN_SECRET;
  const scheduler = Boolean(secret && constantEqual(request.headers.get('authorization') ?? '',`Bearer ${secret}`));
  if (!scheduler && (!await getAdminSession() || request.headers.get('origin') !== request.nextUrl.origin)) return NextResponse.json({error:'Not authorized.'},{status:401});
  const result = await runSocialAgent(scheduler);
  return NextResponse.json(result,{status:'error' in result ? 502 : 200,headers:{'Cache-Control':'no-store'}});
}
