import { NextRequest, NextResponse } from "next/server";
import { adminAuth } from "@/lib/firebaseAdmin";
import { SESSION_COOKIE } from "@/lib/session";

const FIVE_DAYS_MS = 60 * 60 * 24 * 5 * 1000;

// Exchanges a freshly-minted Firebase ID token (from client-side
// signInWithEmailAndPassword) for an httpOnly session cookie, after
// confirming the user actually carries the `role: admin` custom claim.
// This is the only place that claim is trusted from a token the client
// handed us — every other check re-verifies the cookie server-side.
export async function POST(request: NextRequest) {
  const { idToken } = await request.json();
  if (!idToken || typeof idToken !== "string") {
    return NextResponse.json({ error: "Missing idToken" }, { status: 400 });
  }

  let decoded;
  try {
    decoded = await adminAuth.verifyIdToken(idToken, true);
  } catch {
    return NextResponse.json({ error: "Invalid or expired token" }, { status: 401 });
  }

  const role = (decoded.role as string | undefined) ?? (decoded.admin ? "admin" : null);
  if (role !== "admin") {
    return NextResponse.json(
      { error: "This account does not have Mission Control access." },
      { status: 403 }
    );
  }

  const sessionCookie = await adminAuth.createSessionCookie(idToken, { expiresIn: FIVE_DAYS_MS });

  const response = NextResponse.json({ ok: true });
  response.cookies.set(SESSION_COOKIE, sessionCookie, {
    maxAge: FIVE_DAYS_MS / 1000,
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/"
  });
  return response;
}

export async function DELETE() {
  const response = NextResponse.json({ ok: true });
  response.cookies.set(SESSION_COOKIE, "", { maxAge: 0, path: "/" });
  return response;
}
