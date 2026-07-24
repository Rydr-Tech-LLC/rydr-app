export const MISSION_CONTROL_DOMAIN = "rydr-go.com";
export const MISSION_CONTROL_PATH_HEADER = "x-mission-control-path";

export type MissionControlRole = "admin" | "marketing";

export function homeForRole(role: MissionControlRole) {
  return role === "marketing" ? "/campus-growth" : "/dashboard";
}

export function canAccessMissionControlPath(role: MissionControlRole, pathname: string) {
  if (role === "admin") return true;
  return pathname === "/settings" || pathname === "/campus-growth" || pathname.startsWith("/campus-growth/");
}

export function isMissionControlRole(value: unknown): value is MissionControlRole {
  return value === "admin" || value === "marketing";
}

export function isStaffEmail(email: string | null | undefined) {
  return Boolean(email?.toLowerCase().endsWith(`@${MISSION_CONTROL_DOMAIN}`));
}
