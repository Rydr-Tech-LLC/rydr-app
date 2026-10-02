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
    cashHubBillingEnabled: data.cashHubBillingEnabled === true,
    cashHubMonthlyFeeCents: typeof data.cashHubMonthlyFeeCents === "number" ? data.cashHubMonthlyFeeCents : 499,
    cashHubBillingLaunchAt: data.cashHubBillingLaunchAt ?? null,
    updatedAt: data.updatedAt ?? null,
    updatedBy: data.updatedBy ?? null
  });
}

export async function PATCH(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json()) as { termsAcceptanceEnabled?: unknown; cashHubBillingEnabled?: unknown; reason?: unknown };
  if (typeof body.cashHubBillingEnabled === "boolean") {
    const enabled = body.cashHubBillingEnabled;
    const reason = typeof body.reason === "string" ? body.reason : undefined;
    const snap = await configRef().get();
    const current = snap.data() ?? {};
    const wasEnabled = current.cashHubBillingEnabled === true;
    await configRef().set({
      cashHubBillingEnabled: enabled,
      cashHubMonthlyFeeCents: 499,
      cashHubBillingLaunchAt: enabled && !wasEnabled ? FieldValue.serverTimestamp() : current.cashHubBillingLaunchAt ?? null,
      cashHubBillingDisabledAt: !enabled && wasEnabled ? FieldValue.serverTimestamp() : current.cashHubBillingDisabledAt ?? null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: session.uid,
      updatedByEmail: session.email ?? null
    }, { merge: true });
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: enabled ? "Cash Hub Billing Enabled" : "Cash Hub Billing Disabled",
      targetType: "platformConfig",
      targetId: "cashRydrHub",
      reason,
      metadata: { feeCents: 499, collectionSource: "dispatch_earnings" }
    });
    return NextResponse.json({ ok: true, cashHubBillingEnabled: enabled, cashHubMonthlyFeeCents: 499 });
  }
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
      ...(!enabled ? { cashHubBillingEnabled: false, cashHubBillingDisabledAt: FieldValue.serverTimestamp() } : {}),
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
