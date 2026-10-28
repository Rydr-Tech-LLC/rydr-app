export function reportWindow(now: Date, date: string) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(now).map(p => [p.type, p.value]));
  const day = `${parts.year}-${parts.month}-${parts.day}`;
  return { day, due: /^\d{4}-\d{2}-\d{2}$/.test(date) && day === date && Number(parts.hour) * 60 + Number(parts.minute) >= 17 * 60 + 30 };
}

type RecordData = Record<string, any>;
export function summarizeShift(day: string, messages: RecordData[], runs: RecordData[], leads: RecordData[], shiftEnd: number) {
  const leadMap = new Map(leads.map(l => [l.id, l]));
  const outgoing = messages.filter(m => m.direction === "outbound" && m.status === "sent" && ["initial", "followup"].includes(m.kind) && (m.sentAt ?? m.createdAt) < shiftEnd);
  const replies = messages.filter(m => m.direction === "inbound");
  const issues = [
    ...runs.flatMap(r => [r.error, ...(r.warnings ?? [])].filter(Boolean).map(String)),
    ...messages.filter(m => ["unknown", "sending"].includes(m.status)).map(m => `Unconfirmed send to ${m.to ?? "unknown recipient"}: ${m.error || m.status}`),
    ...leads.filter(l => /^email\.(bounced|complained|failed|suppressed)$/.test(l.reason ?? "")).map(l => `${l.name || l.email}: ${l.reason}`),
  ];
  if (!runs.length) issues.push("No completed worker batches were recorded during the shift. Check the GitHub scheduler and campaign status.");
  const contactLines = outgoing.map(m => { const l = leadMap.get(m.leadId); return `${l?.name || "Organization unavailable"} | ${l?.campusName || "Campus unavailable"} | ${m.to} | ${m.kind === "initial" ? "Initial outreach" : "Follow-up"} | ${m.deliveryEvent === "email.delivered" ? "Delivery confirmed" : "Provider accepted; delivery not confirmed in records"}`; });
  return {
    initial: outgoing.filter(m => m.kind === "initial").length,
    followups: outgoing.filter(m => m.kind === "followup").length,
    replies: replies.length,
    body: [`Rowen's shift report for ${day} · 9 a.m.–5 p.m. Eastern`,
      `Initial outreach: ${outgoing.filter(m => m.kind === "initial").length}\nFollow-ups: ${outgoing.filter(m => m.kind === "followup").length}\nTotal emails accepted by provider: ${outgoing.length}\nReplies received today by report time: ${replies.length}\nCompleted worker batches: ${runs.length}`,
      `Contacts\n${contactLines.join("\n") || "No outreach or follow-up emails were recorded."}`,
      `Replies\n${replies.map(m => `${m.from}: ${m.subject}`).join("\n") || "No campaign replies recorded by report time."}`,
      `Issues and warnings\n${[...new Set(issues)].join("\n") || "No issues recorded."}`,
      "Counts exclude setup tests, simulations, and manual inbox responses. Provider acceptance is not proof of delivery. Delivery events and replies may arrive later. This report does not imply that recorded messages were read.",
      "Review Mission Control: https://rydr-app-missioncontrol.vercel.app/workspaces/live-beta/campus-growth/agent"].join("\n\n")
  };
}
