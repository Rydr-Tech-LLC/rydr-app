import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { getWorkspaceDb, getWorkspaceStorage } from "@/lib/firebaseAdmin";
import { uploadedDocumentPath } from "@/lib/driverDocumentReview";

export async function GET(_request: NextRequest, props: { params: Promise<{ uid: string; kind: string; side: string }> }) {
  if (!await getAdminSession()) return NextResponse.json({ error: "Admin access required" }, { status: 401 });
  const { uid, kind, side } = await props.params;
  const snapshot = await (await getWorkspaceDb()).collection("drivers").doc(uid).get();
  if (!snapshot.exists) return NextResponse.json({ error: "Driver not found" }, { status: 404 });
  const path = uploadedDocumentPath(snapshot.data(), uid, kind, side);
  if (!path) return NextResponse.json({ error: "Uploaded document not found" }, { status: 404 });
  const bucket = (await getWorkspaceStorage()).bucket();
  try {
    const file = bucket.file(path);
    const [metadata] = await file.getMetadata();
    if (!Number.isFinite(Number(metadata.size)) || Number(metadata.size) > 15 * 1024 * 1024) return NextResponse.json({ error: "Document is too large to preview" }, { status: 413 });
    const contentType = metadata.contentType ?? "application/octet-stream";
    if (!["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "application/pdf"].includes(contentType)) return NextResponse.json({ error: "Unsupported document preview" }, { status: 415 });
    const [bytes] = await file.download();
    return new NextResponse(new Uint8Array(bytes), { headers: { "Content-Type": contentType, "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "sandbox" } });
  } catch (error: any) {
    if (error?.code === 404) return NextResponse.json({ error: "Upload could not be found" }, { status: 404 });
    return NextResponse.json({ error: "Document preview unavailable; try again later" }, { status: 503 });
  }
}
