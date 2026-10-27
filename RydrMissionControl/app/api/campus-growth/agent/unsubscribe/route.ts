import { NextRequest, NextResponse } from "next/server";
import { unsubscribe } from "@/lib/marketingAgent";

// GET deliberately does not unsubscribe: mail scanners routinely open links.
export async function GET() {
  return new NextResponse(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rydr outreach preferences</title><body style="font:18px system-ui;max-width:560px;margin:80px auto;padding:24px"><h1>Stop Rydr campus invitations</h1><p>Select below to stop marketing-agent outreach to this address.</p><form method="post"><button type="submit" style="padding:12px 20px">Unsubscribe</button></form></body></html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'" } });
}

export async function POST(request: NextRequest) {
  try {
    await unsubscribe(request.nextUrl.searchParams.get("token") ?? "");
    return new NextResponse("You have been unsubscribed from Rydr marketing-agent outreach.", { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  } catch {
    return new NextResponse("This unsubscribe link is invalid. Contact khris.nunnally@rydr-go.com for help.", { status: 400 });
  }
}
