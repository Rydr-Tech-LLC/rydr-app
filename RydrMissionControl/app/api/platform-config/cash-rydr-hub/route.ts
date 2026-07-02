import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

const configRef = () => adminDb.collection("platformConfig").doc("cashRydrHub");

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const snap = await configRef().get();
  const data = snap.data() ?? {};

  return NextResponse.json({
    termsAcceptanceEnabled: data.termsAcceptanceEnabled === true,
    updatedAt: data.updatedAt ?? null,
    updatedBy: data.updatedBy ?? null
  });
}

export async function PATCH(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json()) as { termsAcceptanceEnabled?: unknown; reason?: unknown };
  if (typeof body.termsAcceptanceEnabled !== "boolean") {
    return NextResponse.json({ error: "termsAcceptanceEnabled must be a boolean" }, { status: 400 });
  }

  const enabled = body.termsAcceptanceEnabled;
  const reason = typeof body.reason === "string" ? body.reason : undefined;

  await configRef().set(
    {
      termsAcceptanceEnabled: enabled,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: session.uid,
      updatedByEmail: session.email ?? null
    },
    { merge: true }
  );

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: enabled ? "Cash Hub Terms Acceptance Enabled" : "Cash Hub Terms Acceptance Disabled",
    targetType: "platformConfig",
    targetId: "cashRydrHub",
    reason
  });

  return NextResponse.json({ ok: true, termsAcceptanceEnabled: enabled });
}
