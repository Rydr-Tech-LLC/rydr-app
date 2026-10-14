import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { adminDb, adminStorage } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { DOCUMENT_KINDS, documentDeadline, currentDocument } from "../../../../../../rydr-backend/firebase/functions/src/services/driverCompliancePolicy";
export async function POST(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Admin access required" }, { status: 401 });
  const { uid } = await props.params;
  const body = await request.json();
  if (!DOCUMENT_KINDS.includes(body.kind) || body.verified !== true) return NextResponse.json({ error: "Confirm the uploaded document has been verified" }, { status: 422 });
  const deadline = documentDeadline(body.expirationDate);
  if (typeof body.expirationDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(body.expirationDate) || !Number.isFinite(deadline) || deadline <= Date.now()) return NextResponse.json({ error: "A current, verified expiration date is required" }, { status: 422 });
  const path = typeof body.storagePath === "string" ? body.storagePath.trim() : "";
  if (!path.startsWith(`driverDocuments/${uid}/${body.kind}/`)) return NextResponse.json({ error: "Choose an uploaded document owned by this driver" }, { status: 422 });
  const bucket = adminStorage.bucket(process.env.FIREBASE_STORAGE_BUCKET || process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET || "rydrapp-c7ec1.firebasestorage.app");
  const [exists] = await bucket.file(path).exists();
  if (!exists) return NextResponse.json({ error: "Uploaded document could not be found" }, { status: 422 });
  const ref = adminDb.collection("drivers").doc(uid);
  try {
    await adminDb.runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new Error("Driver not found");
      const driver = snap.data() ?? {};
      const current = driver.documents?.[body.kind] ?? currentDocument(driver, body.kind);
      if (current.storagePath && current.storagePath !== path) throw new Error("A newer document was uploaded. Refresh and review that document.");
      const record = { ...Object.fromEntries(Object.entries(current).filter(([, value]) => value !== undefined && value !== null)), status: "approved", expirationDate: body.expirationDate, storagePath: path, reviewedBy: session.uid, reviewedAt: FieldValue.serverTimestamp(), reviewReason: "Mission Control verified the uploaded document and expiration date" };
      tx.update(ref, { [`documents.${body.kind}`]: { ...record, approvedRecord: { status: "approved", expirationDate: body.expirationDate, storagePath: path, reviewedBy: session.uid, reviewedAt: FieldValue.serverTimestamp() } }, updatedAt: FieldValue.serverTimestamp() });
    });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Verification failed" }, { status: 409 }); }
  await writeAuditLog({ adminUid: session.uid, adminEmail: session.email ?? undefined, action: "Driver document expiration verified", targetType: "driver", targetId: uid, metadata: { kind: body.kind, expirationDate: body.expirationDate } });
  return NextResponse.json({ ok: true });
}
