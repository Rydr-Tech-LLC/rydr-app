import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { duplicatePromotion, setPromotionStatus, type PromotionStatus } from "@/lib/promotions";

type PromotionAction = "activate" | "pause" | "schedule" | "end" | "archive" | "reuse";

const statusByAction: Partial<Record<PromotionAction, PromotionStatus>> = {
  activate: "active",
  pause: "paused",
  schedule: "scheduled",
  end: "ended",
  archive: "archived"
};

export async function POST(request: NextRequest, { params }: { params: { promotionId: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => ({}))) as { action?: PromotionAction };
  if (!body.action) return NextResponse.json({ error: "Promotion action is required." }, { status: 400 });

  try {
    if (body.action === "reuse") {
      const newPromotionId = await duplicatePromotion(params.promotionId, session);
      await writeAuditLog({
        adminUid: session.uid,
        adminEmail: session.email ?? undefined,
        action: "Promotion Reused",
        targetType: "promotion",
        targetId: newPromotionId,
        metadata: { sourcePromotionId: params.promotionId }
      });
      return NextResponse.json({ ok: true, newPromotionId });
    }

    const status = statusByAction[body.action];
    if (!status) return NextResponse.json({ error: "Unsupported promotion action." }, { status: 400 });

    await setPromotionStatus(params.promotionId, status, session);
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: `Promotion ${status[0]!.toUpperCase()}${status.slice(1)}`,
      targetType: "promotion",
      targetId: params.promotionId
    });
    return NextResponse.json({ ok: true, status });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Promotion action failed." }, { status: 400 });
  }
}
