import "server-only";
import { getWorkspaceDb } from "./firebaseAdmin";
import { currentWorkspace } from "./workspace";
import { localTimeToISO } from "../../rydr-backend/services/stripe/promotionPolicy";
import { notificationService } from "../src/services/notifications/NotificationService";
import { reportWindow, summarizeShift } from "./marketingShiftReportPolicy";

// One requested first-shift report. Date/recipient are server settings, never request input.
export async function sendDueShiftReport() {
  const now = new Date();
  const { day, due } = reportWindow(now, process.env.MARKETING_AGENT_REPORT_DATE ?? "");
  const recipient = process.env.MARKETING_AGENT_REPORT_TO;
  if (!due || !recipient || await currentWorkspace() !== "live-beta") return { skipped: true };
  const db = await getWorkspaceDb();
  const campaign = db.collection("marketingAgentCampaigns").doc("student-beta-october-2026");
  const reportRef = campaign.collection("shiftReports").doc(day);
  if ((await reportRef.get()).exists) return { skipped: true, reason: "Report already claimed; inspect its delivery record before retrying." };
  const start = Date.parse(localTimeToISO(`${day}T09:00`));
  const end = Date.parse(localTimeToISO(`${day}T17:00`));
  const [messageDocs, runDocs, leadDocs] = await Promise.all([
    campaign.collection("messages").where("createdAt", ">=", start).where("createdAt", "<=", now.getTime()).limit(1001).get(),
    campaign.collection("runs").where("startedAt", ">=", start).where("startedAt", "<", end).limit(1001).get(),
    campaign.collection("leads").limit(10001).get(),
  ]);
  if (messageDocs.size > 1000 || runDocs.size > 1000 || leadDocs.size > 10000) throw new Error("Shift report exceeds query bounds; manual review required.");
  const report = summarizeShift(day, messageDocs.docs.map(d => d.data()), runDocs.docs.map(d => d.data()), leadDocs.docs.map(d => ({ ...d.data(), id: d.id })), end);
  const claimed = await db.runTransaction(async tx => {
    if ((await tx.get(reportRef)).exists) return false;
    tx.create(reportRef, { status: "sending", recipient, day, createdAt: now.getTime(), ...report });
    return true;
  });
  if (!claimed) return { skipped: true };
  // Never blindly retry an ambiguous external send, even beyond Resend's idempotency window.
  try {
    const result = await notificationService.sendGenericEmail({
      from: "Rowen | Rydr Tech LLC <marketing@rydr-go.com>", to: recipient, replyTo: "support@rydr-go.com",
      subject: `Rowen shift report — ${day}`, body: report.body, eyebrow: "Rydr Mission Control · Shift report",
      idempotencyKey: `rowen-shift-report/live-beta/${day}`,
    });
    await reportRef.update({ status: result.ok ? "sent" : "unknown", providerMessageId: result.providerMessageId ?? null, error: result.error ?? "", finishedAt: Date.now() });
    if (result.providerMessageId) await db.collection("marketingAgentDeliveryIndex").doc(result.providerMessageId).set({ reportId: day });
    if (!result.ok) throw new Error("Shift report delivery unconfirmed; inspect the report record.");
    return { sent: true };
  } catch (error) {
    await reportRef.update({ status: "unknown", error: "Delivery outcome requires provider reconciliation", finishedAt: Date.now() });
    throw error;
  }
}
