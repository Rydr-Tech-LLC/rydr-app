import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { getPromotion, setPromotionStatus, updatePromotion } from "@/lib/promotions";

export async function GET(_request: NextRequest, { params }: { params: { promotionId: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const promotion = await getPromotion(params.promotionId);
  if (!promotion) return NextResponse.json({ error: "Promotion not found." }, { status: 404 });
  return NextResponse.json({ promotion });
}

export async function PATCH(request: NextRequest, { params }: { params: { promotionId: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid promotion payload." }, { status: 400 });

  try {
    await updatePromotion(params.promotionId, body, session);
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Promotion Updated",
      targetType: "promotion",
      targetId: params.promotionId,
      metadata: { title: body.title, type: body.type, status: body.status }
    });
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Promotion could not be updated." }, { status: 400 });
  }
}

export async function DELETE(_request: NextRequest, { params }: { params: { promotionId: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  try {
    await setPromotionStatus(params.promotionId, "archived", session);
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Promotion Archived",
      targetType: "promotion",
      targetId: params.promotionId
    });
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Promotion could not be archived." }, { status: 400 });
  }
}
