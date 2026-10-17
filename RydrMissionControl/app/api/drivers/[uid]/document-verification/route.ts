import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { getWorkspaceDb, getWorkspaceStorage } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { DOCUMENT_KINDS, documentDeadline, latestDocument } from "../../../../../../rydr-backend/firebase/functions/src/services/driverCompliancePolicy";
import { declineReason } from "../../../../../../rydr-backend/firebase/functions/src/services/documentReviewFeedback";
export async function POST(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Admin access required" }, { status: 401 });
  const { uid } = await props.params;
  const body = await request.json();
  const rejected = body.decision === "reject";
  if (!DOCUMENT_KINDS.includes(body.kind) || (!rejected && body.verified !== true)) return NextResponse.json({ error: "Choose a document and confirm your review decision" }, { status: 422 });
  let reason = "Mission Control verified the uploaded document and expiration date";
  if (rejected) {
    try { reason = declineReason(body.reasonCode, body.note); }
    catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Choose a decline reason" }, { status: 422 }); }
  } else {
    const deadline = documentDeadline(body.expirationDate);
    if (typeof body.expirationDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(body.expirationDate) || !Number.isFinite(deadline) || deadline <= Date.now()) return NextResponse.json({ error: "A current, verified expiration date is required" }, { status: 422 });
  }
  const path = typeof body.storagePath === "string" ? body.storagePath.trim() : "";
  if (!path.startsWith(`driverDocuments/${uid}/${body.kind}/`) || path.split('/').some((part: string) => part === '..' || part === '.')) return NextResponse.json({ error: "Choose an uploaded document owned by this driver" }, { status: 422 });
  const bucket = (await getWorkspaceStorage()).bucket();
  const [exists] = await bucket.file(path).exists();
  if (!exists) return NextResponse.json({ error: "Uploaded document could not be found" }, { status: 422 });
  const db = await getWorkspaceDb(), ref = db.collection("drivers").doc(uid), reviewId = randomUUID();
  try {
    await db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new Error("Driver not found");
      const current = latestDocument(snap.data() ?? {}, body.kind);
      if (current.storagePath !== path || String(current.reviewId ?? '') !== String(body.reviewId ?? '')) throw new Error("A newer document or review exists. Refresh and review that document.");
      const now = FieldValue.serverTimestamp();
      const record = { ...Object.fromEntries(Object.entries(current).filter(([, value]) => value !== undefined && value !== null)), status: rejected ? "rejected" : "approved", storagePath: path, reviewedBy: session.uid, reviewedAt: now, reviewReason: reason, driverFacingReason: rejected ? reason : null, declineReasonCode: rejected ? body.reasonCode : null, manualReviewId: reviewId, reviewId, manualReviewStoragePath: path, manualReviewGeneration: current.latestGeneration ?? null };
      const document = rejected ? record : { ...record, expirationDate: body.expirationDate, approvedRecord: { status: "approved", expirationDate: body.expirationDate, storagePath: path, reviewedBy: session.uid, reviewedAt: now } };
      tx.update(ref, { [`documents.${body.kind}`]: document, updatedAt: now });
      tx.set(ref.collection('documentReviews').doc(reviewId), { documentType: body.kind, status: record.status, reviewReason: reason, storagePath: path, reviewedBy: session.uid, reviewedAt: now, source: 'mission-control' });
    });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Review failed" }, { status: 409 }); }
  await writeAuditLog({ adminUid: session.uid, adminEmail: session.email ?? undefined, action: rejected ? "Driver document declined" : "Driver document expiration verified", targetType: "driver", targetId: uid, metadata: { kind: body.kind, reviewId, ...(rejected ? { reasonCode: body.reasonCode, reason } : { expirationDate: body.expirationDate }) } });
  return NextResponse.json({ ok: true });
}
