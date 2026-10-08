import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { deleteAccount, restoreRejectedDeletionRequest, type AccountRole } from "@/lib/accountDeletion";
import type { AccountDeletionRequestRecord } from "@/lib/types";

type Action = "complete" | "reject";

export async function POST(request: NextRequest, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { action, reason } = (await request.json()) as { action: Action; reason?: string };
  if (!["complete", "reject"].includes(action)) {
    return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }

  const requestRef = adminDb.collection("accountDeletionRequests").doc(params.id);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) return NextResponse.json({ error: "Request not found" }, { status: 404 });
  const deletionRequest = requestSnap.data() as AccountDeletionRequestRecord;
  const uid = deletionRequest.uid;
  const roles: AccountRole[] = Array.isArray(deletionRequest.roles) && deletionRequest.roles.length > 0
    ? deletionRequest.roles
    : [deletionRequest.role === "driver" ? "driver" : "rider"];

  if (action === "reject") {
    await restoreRejectedDeletionRequest(uid, roles, deletionRequest.priorAccountStatuses);
    await requestRef.set(
      { status: "rejected", rejectionReason: reason ?? null, processedAt: FieldValue.serverTimestamp(), processedBy: session.uid },
      { merge: true }
    );
    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Account Deletion Rejected",
      targetType: "accountDeletion",
      targetId: params.id,
      reason
    });
    return NextResponse.json({ ok: true });
  }

  // action === "complete"
  await requestRef.set({ status: "processing", processedBy: session.uid }, { merge: true });

  try {
    const deletionResult = await deleteAccount({
      uid,
      adminUid: session.uid,
      requestId: params.id,
      mode: "anonymize"
    });

    await requestRef.set(
      { status: "completed", processedAt: FieldValue.serverTimestamp(), processedBy: session.uid },
      { merge: true }
    );

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Account Deletion Completed",
      targetType: "accountDeletion",
      targetId: params.id,
      reason: deletionResult.stripe.some(({ result }) => (result as { skipped?: boolean }).skipped)
        ? "Stripe cleanup skipped — see logs"
        : undefined
    });

    return NextResponse.json({ ok: true, ...deletionResult });
  } catch (err) {
    // Roll the request back to "requested" so it stays in the queue for a
    // retry rather than silently disappearing mid-failure.
    await requestRef.set({ status: "requested" }, { merge: true });
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
