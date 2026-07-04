import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { writeAuditLog } from "@/lib/auditLog";
import { adminDb } from "@/lib/firebaseAdmin";
import { requireAdminSession } from "@/lib/session";
import { notificationService } from "@/src/services/notifications/NotificationService";

type WaitlistDecision = "approved" | "rejected" | "pending";

interface DecisionBody {
  decision?: unknown;
  reason?: unknown;
}

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  let session;
  try {
    session = await requireAdminSession();
  } catch {
    return NextResponse.json({ error: "Unauthorized." }, { status: 401 });
  }

  const body = (await request.json().catch(() => null)) as DecisionBody | null;
  const decision = cleanDecision(body?.decision);
  const reason = cleanReason(body?.reason);

  if (!decision) {
    return NextResponse.json({ error: "Decision must be approved, rejected, or pending." }, { status: 400 });
  }

  if (decision === "rejected" && !reason) {
    return NextResponse.json({ error: "A rejection reason is required." }, { status: 400 });
  }

  const waitlistRef = adminDb.collection("betaWaitlist").doc(params.id);
  const snap = await waitlistRef.get();
  if (!snap.exists) {
    return NextResponse.json({ error: "Waitlist application not found." }, { status: 404 });
  }

  const data = snap.data() ?? {};
  const email = typeof data.email === "string" ? data.email : "";
  const firstName = typeof data.firstName === "string" ? data.firstName : undefined;
  const role = data.role === "driver" || data.role === "rider" ? data.role : undefined;
  const phoneNumber = normalizeE164Phone(data.phoneNumber);

  const update: Record<string, unknown> = {
    status: decision,
    reviewedAt: FieldValue.serverTimestamp(),
    reviewedBy: session.uid,
    reviewedByEmail: session.email,
    updatedAt: FieldValue.serverTimestamp()
  };

  if (decision === "approved") {
    update.approvedAt = FieldValue.serverTimestamp();
    update.approvedBy = session.uid;
    update.rejectedAt = FieldValue.delete();
    update.rejectedBy = FieldValue.delete();
    update.rejectionReason = FieldValue.delete();
  } else if (decision === "rejected") {
    update.rejectedAt = FieldValue.serverTimestamp();
    update.rejectedBy = session.uid;
    update.rejectionReason = reason;
    update.approvedAt = FieldValue.delete();
    update.approvedBy = FieldValue.delete();
  } else {
    update.approvedAt = FieldValue.delete();
    update.approvedBy = FieldValue.delete();
    update.rejectedAt = FieldValue.delete();
    update.rejectedBy = FieldValue.delete();
    update.rejectionReason = FieldValue.delete();
  }

  await waitlistRef.set(update, { merge: true });

  if (role && phoneNumber) {
    const inviteRef = adminDb.collection("betaInvites").doc(role).collection("phones").doc(phoneNumber);
    if (decision === "approved") {
      await inviteRef.set(
        {
          role,
          phoneNumber,
          email,
          waitlistId: params.id,
          status: "approved",
          approvedAt: FieldValue.serverTimestamp(),
          approvedBy: session.uid,
          updatedAt: FieldValue.serverTimestamp()
        },
        { merge: true }
      );
    } else {
      await inviteRef.set(
        {
          role,
          phoneNumber,
          email,
          waitlistId: params.id,
          status: decision,
          updatedAt: FieldValue.serverTimestamp()
        },
        { merge: true }
      );
    }
  }

  let emailStatus: "not_sent" | "sent" | "failed" = "not_sent";
  let emailError: string | undefined;
  let emailProviderId: string | null | undefined;

  if (decision === "approved" && email) {
    const result = await notificationService.sendBetaApproval({ to: email, firstName });
    emailStatus = result.ok ? "sent" : "failed";
    emailError = result.error;
    emailProviderId = result.providerMessageId;

    await waitlistRef.set(
      {
        approvalEmailStatus: emailStatus,
        approvalEmailSentAt: result.ok ? FieldValue.serverTimestamp() : null,
        approvalEmailError: result.ok ? FieldValue.delete() : result.error,
        approvalEmailProviderId: result.providerMessageId ?? null
      },
      { merge: true }
    );
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: `waitlist_${decision}`,
    targetType: "betaWaitlist",
    targetId: params.id,
    reason
  });

  return NextResponse.json({
    ok: true,
    status: decision,
    emailStatus,
    emailError,
    emailProviderId
  });
}

function cleanDecision(value: unknown): WaitlistDecision | "" {
  return value === "approved" || value === "rejected" || value === "pending" ? value : "";
}

function cleanReason(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed ? trimmed.slice(0, 500) : undefined;
}

function normalizeE164Phone(value: unknown): string {
  if (typeof value !== "string") return "";
  const digits = value.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  return value.startsWith("+") && digits.length >= 10 ? `+${digits}` : "";
}
