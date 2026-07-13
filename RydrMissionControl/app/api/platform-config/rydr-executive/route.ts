import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

const configRef = () => adminDb.collection("platformConfig").doc("rydrExecutive");

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const snap = await configRef().get();
  const data = snap.data() ?? {};

  return NextResponse.json({
    enabled: data.enabled === true,
    betaPaused: data.betaPaused !== false,
    updatedAt: data.updatedAt ?? null,
    updatedBy: data.updatedBy ?? null
  });
}

export async function PATCH(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json()) as { enabled?: unknown; reason?: unknown };
  if (typeof body.enabled !== "boolean") {
    return NextResponse.json({ error: "enabled must be a boolean" }, { status: 400 });
  }

  const enabled = body.enabled;
  const reason = typeof body.reason === "string" ? body.reason : undefined;

  await configRef().set(
    {
      enabled,
      betaPaused: !enabled,
      disabledRideTypes: enabled ? [] : ["Rydr Executive"],
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: session.uid,
      updatedByEmail: session.email ?? null
    },
    { merge: true }
  );

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: enabled ? "Rydr Executive Beta Enabled" : "Rydr Executive Beta Paused",
    targetType: "platformConfig",
    targetId: "rydrExecutive",
    reason,
    metadata: { enabled }
  });

  return NextResponse.json({ ok: true, enabled, betaPaused: !enabled });
}
