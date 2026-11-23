import { FieldValue } from "firebase-admin/firestore";
import { NextRequest, NextResponse } from "next/server";
import { getWorkspaceAuth, getWorkspaceDb, getWorkspaceStorage } from "@/lib/firebaseAdmin";
import { latestDriverDocument, uploadedDocumentPath } from "@/lib/driverDocumentReview";
import { getAdminSession } from "@/lib/session";
import {
  detectDocumentText,
  reviewDriverProof
} from "../../../../../../rydr-backend/firebase/functions/src/services/documentReviewService";

export const maxDuration = 60;

export async function POST(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Admin access required" }, { status: 401 });

  const { uid } = await props.params;
  const body = await request.json().catch(() => null);
  const kind = body?.kind;
  if ((kind !== "driverLicense" && kind !== "insurance" && kind !== "registration") || typeof body?.reviewId !== "string") {
    return NextResponse.json({ error: "Choose a driver license, insurance or registration upload." }, { status: 422 });
  }

  const [db, storage, auth] = await Promise.all([getWorkspaceDb(), getWorkspaceStorage(), getWorkspaceAuth()]);
  const ref = db.collection("drivers").doc(uid);
  const side = kind === "driverLicense" ? "front" : "single";
  const driver = (await ref.get()).data();
  if (!driver) return NextResponse.json({ error: "Driver not found." }, { status: 404 });

  const record = latestDriverDocument(driver, kind);
  const path = uploadedDocumentPath(driver, uid, kind, side);
  if (!path) return NextResponse.json({ error: "Upload could not be found." }, { status: 404 });
  if ((record.reviewId ?? "") !== body.reviewId || record.status === "pending") {
    return NextResponse.json({ error: "The document review changed. Refresh the page and try again." }, { status: 409 });
  }

  const bucket = storage.bucket();
  let text: string;
  try {
    const token = await auth.app.options.credential?.getAccessToken();
    if (!token?.access_token) throw new Error("OCR credential unavailable");
    text = await detectDocumentText(`gs://${bucket.name}/${path}`, token.access_token);
  } catch {
    return NextResponse.json({ error: "The OCR service could not read this upload. Try again or inspect the document manually." }, { status: 503 });
  }
  const history = ref.collection("documentReviews").doc();

  const saved = await db.runTransaction(async tx => {
    const latestDriver = (await tx.get(ref)).data();
    if (!latestDriver) return false;
    const latest = latestDriverDocument(latestDriver, kind);
    if ((latest.reviewId ?? "") !== body.reviewId || latest.status === "pending"
      || uploadedDocumentPath(latestDriver, uid, kind, side) !== path) return false;

    const { extractedFields, decision } = reviewDriverProof(kind, text, latestDriver);
    const status = decision.status;
    const { reviewReason, checks } = decision;
    const now = FieldValue.serverTimestamp();
    const preservedManualDecision = Boolean(latest.manualReviewId && latest.manualReviewId === latest.reviewId);
    const fields: Record<string, unknown> = {
      extractedFields,
      automationStatus: status,
      automationReason: reviewReason,
      automationReviewedAt: now,
      ocrSchemaVersion: 2
    };
    if (!preservedManualDecision) {
      Object.assign(fields, { status, reviewReason, reviewId: history.id, storagePath: path, lastUploadedSide: side, reviewedAt: now });
      if (status === "approved") {
        fields.expirationDate = extractedFields.expirationDate ?? null;
        fields.approvedRecord = {
          status, extractedFields, expirationDate: extractedFields.expirationDate ?? null,
          storagePath: path, reviewId: history.id, generation: latest.latestGeneration ?? null, reviewedAt: now
        };
      }
    }
    // Updating the document-specific map replaces the OCR fields as a unit,
    // including when the new read could only recover a subset of old fields.
    tx.update(ref, { [`documents.${kind}`]: { ...latest, ...fields }, updatedAt: now });
    tx.set(history, {
      documentType: kind, storagePath: path, storageBucket: bucket.name, extractedFields,
      status, reviewReason, checks, source: "mission-control-ocr", requestedBy: session.uid,
      reviewedByAutomation: true, createdAt: now, reviewedAt: now
    });
    return true;
  });
  if (!saved) return NextResponse.json({ error: "The document review changed. Refresh the page and try again." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
