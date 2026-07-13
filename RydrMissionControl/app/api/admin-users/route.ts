import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { writeAuditLog } from "@/lib/auditLog";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const ADMIN_DOMAIN = "rydr-go.com";
const ADMIN_COLLECTION = "missionControlAdmins";

type AdminAction = "grant" | "revoke";
type AdminCreateAction = AdminAction | "create" | "resetPassword";

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
  const action = normalizeAction(body?.action);
  const temporaryPassword = typeof body?.temporaryPassword === "string" ? body.temporaryPassword : "";
  const displayName = cleanName(body?.displayName);

  if (!email) return NextResponse.json({ error: "A valid @rydr-go.com email is required." }, { status: 400 });
  if (!action) return NextResponse.json({ error: "Action must be create, grant, resetPassword, or revoke." }, { status: 400 });
  if (action === "revoke" && email === session.email?.toLowerCase()) {
    return NextResponse.json({ error: "You cannot revoke your own Mission Control access." }, { status: 400 });
  }

  if (action === "create") {
    const passwordError = validateTemporaryPassword(temporaryPassword);
    if (passwordError) return NextResponse.json({ error: passwordError }, { status: 400 });

    let user;
    try {
      user = await adminAuth.createUser({
        email,
        password: temporaryPassword,
        displayName: displayName || undefined,
        emailVerified: true,
        disabled: false
      });
    } catch (error) {
      const code = errorCode(error);
      if (code === "auth/email-already-exists") {
        return NextResponse.json(
          { error: "A Firebase Auth user already exists for this email. Use Grant Admin or Set Temp Password instead." },
          { status: 409 }
        );
      }
      return NextResponse.json({ error: "Unable to create Firebase Auth user." }, { status: 500 });
    }

    await adminAuth.setCustomUserClaims(user.uid, { role: "admin" });
    await upsertAdminRecord({
      uid: user.uid,
      email,
      status: "active",
      session,
      displayName,
      createdLogin: true,
      passwordStatus: "temporary"
    });

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Mission Control Admin Login Created",
      targetType: "missionControlAdmin",
      targetId: user.uid,
      metadata: { email, action, createdLogin: true, passwordStatus: "temporary" }
    });

    return NextResponse.json({
      ok: true,
      uid: user.uid,
      email,
      status: "active",
      createdLogin: true,
      passwordStatus: "temporary"
    });
  }

  let user;
  try {
    user = await adminAuth.getUserByEmail(email);
  } catch (error) {
    const code = errorCode(error);
    if (code === "auth/user-not-found") {
      return NextResponse.json(
        { error: "No Firebase Auth user exists for that email yet. Use Create Admin Login to create the account and set a temporary password." },
        { status: 404 }
      );
    }
    return NextResponse.json({ error: "Unable to look up Firebase Auth user." }, { status: 500 });
  }

  if (action === "resetPassword") {
    const passwordError = validateTemporaryPassword(temporaryPassword);
    if (passwordError) return NextResponse.json({ error: passwordError }, { status: 400 });

    await adminAuth.updateUser(user.uid, {
      password: temporaryPassword,
      emailVerified: true,
      disabled: false
    });

    const existingClaims = user.customClaims ?? {};
    await adminAuth.setCustomUserClaims(user.uid, { ...existingClaims, role: "admin" });
    await upsertAdminRecord({
      uid: user.uid,
      email,
      status: "active",
      session,
      displayName: user.displayName ?? "",
      passwordStatus: "temporary"
    });

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: "Mission Control Admin Temporary Password Set",
      targetType: "missionControlAdmin",
      targetId: user.uid,
      metadata: { email, action, passwordStatus: "temporary" }
    });

    return NextResponse.json({
      ok: true,
      uid: user.uid,
      email,
      status: "active",
      passwordStatus: "temporary"
    });
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
    await upsertAdminRecord({
      uid: user.uid,
      email,
      status: "active",
      session,
      displayName: user.displayName ?? "",
      createdLogin: false
    });
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

function normalizeAction(value: unknown): AdminCreateAction | null {
  if (value === "create" || value === "grant" || value === "resetPassword" || value === "revoke") return value;
  return null;
}

function cleanName(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, 120);
}

function errorCode(error: unknown): string {
  return typeof error === "object" && error && "code" in error ? String((error as { code?: string }).code) : "";
}

function validateTemporaryPassword(password: string) {
  if (password.length < 10) return "Temporary password must be at least 10 characters.";
  if (!/[A-Z]/.test(password)) return "Temporary password must include an uppercase letter.";
  if (!/[a-z]/.test(password)) return "Temporary password must include a lowercase letter.";
  if (!/[0-9]/.test(password)) return "Temporary password must include a number.";
  if (!/[^A-Za-z0-9]/.test(password)) return "Temporary password must include a symbol.";
  return "";
}

async function upsertAdminRecord(input: {
  uid: string;
  email: string;
  status: "active";
  session: Awaited<ReturnType<typeof getAdminSession>> & {};
  displayName?: string;
  createdLogin?: boolean;
  passwordStatus?: "temporary";
}) {
  const payload: Record<string, unknown> = {
    uid: input.uid,
    email: input.email,
    displayName: input.displayName ?? "",
    role: "admin",
    status: input.status,
    passwordStatus: input.passwordStatus ?? FieldValue.delete(),
    temporaryPasswordSetAt: input.passwordStatus === "temporary" ? FieldValue.serverTimestamp() : FieldValue.delete(),
    grantedAt: FieldValue.serverTimestamp(),
    grantedBy: input.session.uid,
    grantedByEmail: input.session.email ?? null,
    revokedAt: FieldValue.delete(),
    revokedBy: FieldValue.delete(),
    revokedByEmail: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp()
  };
  if (typeof input.createdLogin === "boolean") {
    payload.createdLogin = input.createdLogin;
  }
  await adminDb.collection(ADMIN_COLLECTION).doc(input.uid).set(payload, { merge: true });
}
