// Scheduler entry point. No local credentials or message contents are logged.
// The server enforces the saved campaign dates, including later extensions.
const origin = process.env.MARKETING_AGENT_PUBLIC_URL;
const secret = process.env.MARKETING_AGENT_RUN_SECRET;
if (!origin || new URL(origin).protocol !== "https:" || !secret) {
  throw new Error("Configure MARKETING_AGENT_PUBLIC_URL and MARKETING_AGENT_RUN_SECRET.");
}
const response = await fetch(new URL("/api/campus-growth/agent/run", origin), {
  method: "POST", redirect: "error", signal: AbortSignal.timeout(295_000),
  headers: { Authorization: `Bearer ${secret}`, "x-rydr-workspace": "live-beta", "Content-Type": "application/json" },
  body: "{}"
});
if (!response.ok) throw new Error(`Marketing agent run failed (${response.status}); inspect Mission Control run history.`);
const result = await response.json();
console.log(JSON.stringify({ skipped: result.skipped ?? false, drafted: result.drafted ?? 0, sent: result.sent ?? 0 }));
