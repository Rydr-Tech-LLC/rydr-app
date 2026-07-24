import "server-only";
import { cookies } from "next/headers";
import { adminAuth } from "./firebaseAdmin";
import {
  isMissionControlRole,
  isStaffEmail,
  type MissionControlRole
} from "./missionControlAccess";

export const SESSION_COOKIE = process.env.SESSION_COOKIE_NAME || "rydr_mc_session";
export { homeForRole, isMissionControlRole, isStaffEmail } from "./missionControlAccess";
export type { MissionControlRole } from "./missionControlAccess";

export interface MissionControlSession {
  uid: string;
  email: string | null;
  role: MissionControlRole;
}

/**
 * Verifies the session cookie server-side against Firebase Admin and
 * confirms an approved Mission Control role and staff email domain.
 */
export async function getMissionControlSession(): Promise<MissionControlSession | null> {
  const cookieStore = cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE)?.value;
  if (!sessionCookie) return null;

  try {
    const decoded = await adminAuth.verifySessionCookie(sessionCookie, true);
    const role = (decoded.role as string | undefined) ?? (decoded.admin ? "admin" : null);
    const email = decoded.email?.toLowerCase() ?? null;
    if (!isMissionControlRole(role) || !isStaffEmail(email)) return null;
    return { uid: decoded.uid, email: decoded.email ?? null, role };
  } catch {
    return null;
  }
}

export async function getAdminSession(): Promise<MissionControlSession | null> {
  const session = await getMissionControlSession();
  return session?.role === "admin" ? session : null;
}

export async function getCampusGrowthSession(): Promise<MissionControlSession | null> {
  return getMissionControlSession();
}

export async function requireAdminSession(): Promise<MissionControlSession> {
  const session = await getAdminSession();
  if (!session) {
    throw new Error("UNAUTHENTICATED");
  }
  return session;
}
