import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { stripeCleanupStatus } from "@/lib/stripeCleanupStatus";

export const dynamic = "force-dynamic";
export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const result = await stripeCleanupStatus(session.uid);
  return NextResponse.json(result, { status: result.configured ? 200 : 503, headers: { "Cache-Control": "no-store" } });
}
