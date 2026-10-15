/** Calendar dates match the Georgia operations timezone, regardless of server locale. */
export function reportingDay(timestamp: number): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(timestamp);
}
export function inReportingWindow(
  timestamp: number,
  now: number,
  days: number,
): boolean {
  return (
    Number.isFinite(timestamp) &&
    timestamp > 0 &&
    timestamp <= now &&
    reportingDay(timestamp) >= reportingDay(now - (days - 1) * 86400000)
  );
}
export function validSupportRequest(
  body: unknown,
): body is { text?: string; setStatus?: "open" | "closed" } {
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  const value = body as Record<string, unknown>;
  return (
    (value.setStatus === undefined ||
      value.setStatus === "open" ||
      value.setStatus === "closed") &&
    (value.text === undefined ||
      (typeof value.text === "string" && value.text.length <= 10000))
  );
}
