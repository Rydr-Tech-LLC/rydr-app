import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

const configRef = () => adminDb.collection("platformConfig").doc("cashRydrHub");

function newTermsVersion() {
  return `cash-hub-${Date.now()}`;
}

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const snap = await configRef().get();
  const data = snap.data() ?? {};

  return NextResponse.json({
    termsAcceptanceEnabled: data.termsAcceptanceEnabled === true,
    cashHubTermsVersion: typeof data.cashHubTermsVersion === "string" ? data.cashHubTermsVersion : null,
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

  const updatedConfig = await adminDb.runTransaction(async (transaction) => {
    const ref = configRef();
    const snap = await transaction.get(ref);
    const current = snap.data() ?? {};
    const currentVersion = typeof current.cashHubTermsVersion === "string" ? current.cashHubTermsVersion : null;
    const currentEnabled = current.termsAcceptanceEnabled === true;
    const nextVersion = !enabled || !currentVersion ? newTermsVersion() : currentVersion;

    transaction.set(ref, {
      termsAcceptanceEnabled: enabled,
      cashHubTermsVersion: nextVersion,
      disabledAt: !enabled && currentEnabled ? FieldValue.serverTimestamp() : current.disabledAt ?? null,
      enabledAt: enabled && !currentEnabled ? FieldValue.serverTimestamp() : current.enabledAt ?? null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: session.uid,
      updatedByEmail: session.email ?? null
    }, { merge: true });

    return { termsAcceptanceEnabled: enabled, cashHubTermsVersion: nextVersion };
  });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: enabled ? "Cash Hub Terms Acceptance Enabled" : "Cash Hub Terms Acceptance Disabled and Reset",
    targetType: "platformConfig",
    targetId: "cashRydrHub",
    reason,
    metadata: { cashHubTermsVersion: updatedConfig.cashHubTermsVersion }
  });

  return NextResponse.json({ ok: true, ...updatedConfig });
}
