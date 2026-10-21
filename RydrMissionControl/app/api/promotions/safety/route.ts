import { NextRequest, NextResponse } from "next/server";
import { createHash } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session)
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const body = await request.json().catch(() => null);
  const { userId, action, reason, signalId } = body ?? {};
  if (
    typeof userId !== "string" ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(userId) ||
    !["hold", "release", "allow_shared_identity"].includes(action) ||
    typeof reason !== "string" ||
    reason.trim().length < 5 ||
    reason.length > 500 ||
    (action === "allow_shared_identity" &&
      (typeof signalId !== "string" || !/^[a-f0-9]{64}$/.test(signalId)))
  )
    return NextResponse.json(
      {
        error:
          "Choose an account, action and a review reason (5–500 characters).",
      },
      { status: 400 },
    );
  const db = await getWorkspaceDb();
  try {
    await db.runTransaction(async (tx) => {
      const signalRef =
        action === "allow_shared_identity"
          ? db.collection("promotionAbuseSignals").doc(signalId)
          : null;
      const signal = signalRef ? (await tx.get(signalRef)).data() : null;
      if (signalRef && (!signal || signal.userId !== userId))
        throw new Error("Review signal does not belong to this account.");
      const stamp = FieldValue.serverTimestamp();
      if (signalRef && signal) {
        const id = createHash("sha256")
          .update(JSON.stringify([signal.promotionId, userId]))
          .digest("hex");
        tx.set(db.collection("promotionIdentityOverrides").doc(id), {
          allowed: true,
          userId,
          promotionId: signal.promotionId,
          reason: reason.trim(),
          updatedBy: session.uid,
          updatedAt: stamp,
        });
        tx.update(signalRef, {
          status: "allowed",
          reviewedBy: session.uid,
          reviewedAt: stamp,
          reasonForDecision: reason.trim(),
        });
      } else
        tx.set(
          db.collection("promotionAccountControls").doc(userId),
          {
            blocked: action === "hold",
            userId,
            reason: reason.trim(),
            updatedBy: session.uid,
            updatedAt: stamp,
          },
          { merge: true },
        );
      tx.create(db.collection("audits").doc(), {
        adminUid: session.uid,
        action: `Promotion safety: ${action}`,
        targetType: "promotion",
        targetId: userId,
        metadata: { reason: reason.trim(), signalId: signalId ?? null },
        createdAt: stamp,
      });
    });
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Review failed." },
      { status: 400 },
    );
  }
}
