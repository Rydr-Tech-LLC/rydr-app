import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { createPromotion, listPromotions } from "@/lib/promotions";

export async function GET(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const includeArchived = request.nextUrl.searchParams.get("includeArchived") === "1";
  const promotions = await listPromotions(includeArchived);
  return NextResponse.json({ promotions });
}

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid promotion payload." }, { status: 400 });

  try {
    const id = await createPromotion(body, session);
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Promotion Created",
      targetType: "promotion",
      targetId: id,
      metadata: { title: body.title, type: body.type, status: body.status }
    });
    return NextResponse.json({ id }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Promotion could not be created." }, { status: 400 });
  }
}
