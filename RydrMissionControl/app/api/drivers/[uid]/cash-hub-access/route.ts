import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { getAdminSession } from "@/lib/session";

type CashHubAccessAction = "restore" | "pause";

export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => ({}))) as { action?: CashHubAccessAction; reason?: string };
  if (body.action !== "restore" && body.action !== "pause") {
    return NextResponse.json({ error: "Invalid CashRydr Hub access action." }, { status: 400 });
  }

  const driverRef = adminDb.collection("drivers").doc(params.uid);
  const [driverSnap, configSnap] = await Promise.all([
    driverRef.get(),
    adminDb.collection("platformConfig").doc("cashRydrHub").get()
  ]);
  if (!driverSnap.exists) return NextResponse.json({ error: "Driver not found." }, { status: 404 });

  const driver = driverSnap.data() ?? {};
  const config = configSnap.data() ?? {};

  if (body.action === "restore") {
    if (config.termsAcceptanceEnabled !== true) {
      return NextResponse.json({ error: "CashRydr Hub is not currently enabled." }, { status: 409 });
    }
    if (driver.cashHubOptedOut === true) {
      return NextResponse.json({ error: "The driver opted out and must accept CashRydr Hub terms again in the Driver app." }, { status: 409 });
    }
    if (driver.cashHubTermsAccepted !== true || driver.cashHubTermsVersion !== config.cashHubTermsVersion) {
      return NextResponse.json({ error: "The driver must accept the current CashRydr Hub terms first." }, { status: 409 });
    }

    const billing = await driverRef.collection("cashHubBilling").limit(24).get();
    const now = Date.now();
    const hasOverdueFee = billing.docs.some((doc) => {
      const value = doc.data();
      const remaining = Math.max(0, Number(value.remainingCents) || 0);
      const status = String(value.status ?? "");
      const graceEndsAt = value.graceEndsAt?.toMillis?.() ?? Number.POSITIVE_INFINITY;
      return remaining > 0 && (status === "past_due" || status === "pastDue" || graceEndsAt <= now);
    });
    if (hasOverdueFee) {
      return NextResponse.json({ error: "CashRydr Hub access cannot be restored while a monthly fee is past due." }, { status: 409 });
    }

    await driverRef.set({
      cashHubAccessStatus: "active",
      cashHubLateReleaseCount: 0,
      cashHubAccessRestoredAt: FieldValue.serverTimestamp(),
      cashHubAccessRestoredBy: session.uid,
      cashHubAccessReviewReason: FieldValue.delete(),
      cashHubAccessSuspendedAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  } else {
    await driverRef.set({
      cashHubAccessStatus: "suspended",
      cashHubAccessSuspendedAt: FieldValue.serverTimestamp(),
      cashHubAccessReviewReason: body.reason?.trim() || "Paused by Mission Control.",
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: body.action === "restore" ? "CashHub Access Restored" : "CashHub Access Paused",
    targetType: "driver",
    targetId: params.uid,
    reason: body.reason
  });

  return NextResponse.json({ ok: true, status: body.action === "restore" ? "active" : "suspended" });
}
