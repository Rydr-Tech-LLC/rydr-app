import "server-only";
import { cookies } from "next/headers";
import { adminAuth } from "./firebaseAdmin";

export const SESSION_COOKIE = process.env.SESSION_COOKIE_NAME || "rydr_mc_session";

export interface AdminSession {
  uid: string;
  email: string | null;
  role: string | null;
}

/**
 * Verifies the session cookie server-side against Firebase Admin and
 * confirms the `role: "admin"` custom claim. Returns null if there's no
 * valid, current admin session — callers (server layouts, route handlers)
 * are responsible for redirecting/rejecting. This is the one and only
 * gate privileged pages and API routes trust; nothing here relies on
 * anything the client sent except the opaque session cookie itself.
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  const cookieStore = cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE)?.value;
  if (!sessionCookie) return null;

  try {
    const decoded = await adminAuth.verifySessionCookie(sessionCookie, true);
    const role = (decoded.role as string | undefined) ?? (decoded.admin ? "admin" : null);
    if (role !== "admin") return null;
    return { uid: decoded.uid, email: decoded.email ?? null, role };
  } catch {
    return null;
  }
}

export async function requireAdminSession(): Promise<AdminSession> {
  const session = await getAdminSession();
  if (!session) {
    throw new Error("UNAUTHENTICATED");
  }
  return session;
}
