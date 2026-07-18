import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { notificationService } from "@/src/services/notifications/NotificationService";

type AuthAction = "send_password_reset" | "send_email_verification" | "mark_email_verified";

const ACTION_LABEL: Record<AuthAction, string> = {
  send_password_reset: "Driver Password Reset Sent",
  send_email_verification: "Driver Email Verification Sent",
  mark_email_verified: "Driver Email Marked Verified"
};

export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => null)) as { action?: AuthAction } | null;
  const action = body?.action;
  if (!action || !Object.keys(ACTION_LABEL).includes(action)) {
    return NextResponse.json({ error: "Invalid auth action." }, { status: 400 });
  }

  const [driverSnap, user] = await Promise.all([
    adminDb.collection("drivers").doc(params.uid).get(),
    adminAuth.getUser(params.uid).catch(() => null)
  ]);
  if (!driverSnap.exists) return NextResponse.json({ error: "Driver not found." }, { status: 404 });
  if (!user) return NextResponse.json({ error: "Firebase Auth user not found." }, { status: 404 });

  const driver = driverSnap.data() ?? {};
  const email = typeof user.email === "string" && user.email ? user.email : typeof driver.email === "string" ? driver.email : "";
  if (!email) return NextResponse.json({ error: "Driver does not have an email address." }, { status: 400 });

  if (action === "mark_email_verified") {
    await adminAuth.updateUser(params.uid, { emailVerified: true });
    await adminDb.collection("drivers").doc(params.uid).set(
      {
        emailVerified: true,
        emailVerifiedAt: FieldValue.serverTimestamp(),
        emailVerifiedBy: session.uid,
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    await audit(session, action, params.uid, email);
    return NextResponse.json({ ok: true });
  }

  const link =
    action === "send_password_reset"
      ? await adminAuth.generatePasswordResetLink(email)
      : await adminAuth.generateEmailVerificationLink(email);

  const firstName = typeof driver.firstName === "string" && driver.firstName.trim() ? driver.firstName.trim() : "there";
  const result = await notificationService.sendGenericEmail({
    to: email,
    subject: action === "send_password_reset" ? "Reset your Rydr driver password" : "Verify your Rydr driver email",
    title: action === "send_password_reset" ? "Reset your Rydr driver password" : "Verify your Rydr driver email",
    eyebrow: "Rydr Mission Control",
    body:
      action === "send_password_reset"
        ? `Hi ${firstName},\n\nMission Control sent this password reset link for your Rydr driver account:\n\n${link}\n\nIf you did not request this, contact Rydr support.`
        : `Hi ${firstName},\n\nMission Control sent this email verification link for your Rydr driver account:\n\n${link}\n\nIf you did not request this, contact Rydr support.`
  });
  if (!result.ok) {
    return NextResponse.json({ error: result.error ?? "Unable to send email." }, { status: 502 });
  }

  await adminDb.collection("drivers").doc(params.uid).set(
    {
      [action === "send_password_reset" ? "passwordResetSentAt" : "emailVerificationSentAt"]: FieldValue.serverTimestamp(),
      [action === "send_password_reset" ? "passwordResetSentBy" : "emailVerificationSentBy"]: session.uid,
      updatedAt: FieldValue.serverTimestamp()
    },
    { merge: true }
  );
  await audit(session, action, params.uid, email);

  return NextResponse.json({ ok: true });
}

async function audit(
  session: { uid: string; email?: string | null },
  action: AuthAction,
  uid: string,
  email: string
) {
  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: ACTION_LABEL[action],
    targetType: "driver",
    targetId: uid,
    metadata: { email }
  });
}
