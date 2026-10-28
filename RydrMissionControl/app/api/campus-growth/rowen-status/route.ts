import { NextResponse } from 'next/server';
import { getAdminSession } from '@/lib/session';
import { rowenStatus } from '@/lib/rowenStatus';
export const runtime='nodejs';
export async function GET(){
 if(!await getAdminSession())return NextResponse.json({error:'Administrator access required.'},{status:401});
 try{return NextResponse.json(await rowenStatus(),{headers:{'Cache-Control':'no-store'}});}
 catch{return NextResponse.json({error:'Status unavailable. Please refresh.'},{status:503});}
}
