import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { runMarketingAgent } from "@/lib/marketingAgent";
import { sendDueShiftReport } from "@/lib/marketingShiftReport";

export const maxDuration = 300;
export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  const secret = process.env.MARKETING_AGENT_RUN_SECRET;
  const supplied = request.headers.get("authorization") ?? "";
  const expected = secret ? `Bearer ${secret}` : "";
  const scheduler = Boolean(secret && Buffer.byteLength(supplied) === Buffer.byteLength(expected)
    && timingSafeEqual(Buffer.from(supplied), Buffer.from(expected)));
  if (!scheduler && !await getAdminSession()) return NextResponse.json({ error: "Not authorized" }, { status: 401 });
  const result = await runMarketingAgent();
  // Reporting is allowed after the work shift; it does not send outreach or consume its caps.
  const shiftReport = scheduler ? await sendDueShiftReport() : { skipped: true };
  return NextResponse.json({ ...result, shiftReport }, { status: "error" in result && result.error ? 502 : 200 });
}
