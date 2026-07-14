import type { DriverRecord } from "@/lib/types";

export function timeAgo(date?: Date | null): string {
  if (!date) return "—";
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.floor(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

export function toDateSafe(value?: { toDate?: () => Date } | null): Date | null {
  try {
    return value?.toDate ? value.toDate() : null;
  } catch {
    return null;
  }
}

export function fullName(first?: string, last?: string): string {
  const name = [first, last].filter(Boolean).join(" ");
  return name || "Unnamed driver";
}

export function driverFullName(driver: DriverRecord): string {
  const legalParts = [driver.firstName, driver.lastName].map(cleanNamePart).filter(Boolean).join(" ");
  if (legalParts) return legalParts;

  const legacyLegalParts = [driver.legalFirstName, driver.legalLastName].map(cleanNamePart).filter(Boolean).join(" ");
  if (legacyLegalParts) return legacyLegalParts;

  const legalName = cleanNamePart(driver.legalName);
  if (legalName) return legalName;

  const displayName = cleanNamePart(driver.displayName);
  if (displayName && displayName !== "Rydr Driver") return displayName;

  return "Name not collected";
}

export function driverNameCollected(driver: DriverRecord): boolean {
  return driverFullName(driver) !== "Name not collected";
}

function cleanNamePart(value?: string): string {
  return typeof value === "string" ? value.trim() : "";
}
