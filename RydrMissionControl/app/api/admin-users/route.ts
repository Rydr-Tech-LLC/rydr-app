import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { writeAuditLog } from "@/lib/auditLog";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const ADMIN_DOMAIN = "rydr-go.com";
const ADMIN_COLLECTION = "missionControlAdmins";

type AdminAction = "grant" | "revoke";

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const snap = await adminDb.collection(ADMIN_COLLECTION).orderBy("email", "asc").limit(250).get();
  const admins = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  return NextResponse.json({ admins });
}

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = await request.json().catch(() => null);
  const email = normalizeEmail(body?.email);
  const action = body?.action === "revoke" ? "revoke" : body?.action === "grant" ? "grant" : null;

  if (!email) return NextResponse.json({ error: "A valid @rydr-go.com email is required." }, { status: 400 });
  if (!action) return NextResponse.json({ error: "Action must be grant or revoke." }, { status: 400 });
  if (action === "revoke" && email === session.email?.toLowerCase()) {
    return NextResponse.json({ error: "You cannot revoke your own Mission Control access." }, { status: 400 });
  }

  let user;
  try {
    user = await adminAuth.getUserByEmail(email);
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? String((error as { code?: string }).code) : "";
    if (code === "auth/user-not-found") {
      return NextResponse.json(
        { error: "No Firebase Auth user exists for that email yet. Have them create/sign in to the account first, then grant access here." },
        { status: 404 }
      );
    }
    return NextResponse.json({ error: "Unable to look up Firebase Auth user." }, { status: 500 });
  }

  const existingClaims = user.customClaims ?? {};
  const nextClaims = { ...existingClaims };
  if (action === "grant") {
    nextClaims.role = "admin";
  } else {
    delete nextClaims.role;
    delete nextClaims.admin;
  }

  await adminAuth.setCustomUserClaims(user.uid, nextClaims);

  const adminRef = adminDb.collection(ADMIN_COLLECTION).doc(user.uid);
  if (action === "grant") {
    await adminRef.set(
      {
        uid: user.uid,
        email,
        role: "admin",
        status: "active",
        grantedAt: FieldValue.serverTimestamp(),
        grantedBy: session.uid,
        grantedByEmail: session.email ?? null,
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );
  } else {
    await adminRef.set(
      {
        uid: user.uid,
        email,
        role: "admin",
        status: "revoked",
        revokedAt: FieldValue.serverTimestamp(),
        revokedBy: session.uid,
        revokedByEmail: session.email ?? null,
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: action === "grant" ? "Mission Control Admin Granted" : "Mission Control Admin Revoked",
    targetType: "missionControlAdmin",
    targetId: user.uid,
    metadata: { email, action }
  });

  return NextResponse.json({
    ok: true,
    uid: user.uid,
    email,
    status: action === "grant" ? "active" : "revoked"
  });
}

function normalizeEmail(value: unknown): string {
  if (typeof value !== "string") return "";
  const email = value.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return "";
  return email.endsWith(`@${ADMIN_DOMAIN}`) ? email : "";
}
