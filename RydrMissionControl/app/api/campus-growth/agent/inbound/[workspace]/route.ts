import { NextRequest, NextResponse } from "next/server";
import { Resend, type WebhookEventPayload } from "resend";
import { currentWorkspace } from "@/lib/workspace";
import { receiveMarketingEmail, receiveDeliveryEvent } from "@/lib/marketingAgentInbox";
import { normalizeEmailAddress, isNoReplyEmail, MARKETING_AGENT_EMAIL, MARKETING_SUBJECT_TAG } from "@/lib/marketingAgentPolicy";

export const runtime = "nodejs";
export async function POST(request: NextRequest, context: { params: Promise<{ workspace: string }> }) {
  const { workspace } = await context.params;
  if (!["test", "live-beta"].includes(workspace) || workspace !== await currentWorkspace()) return NextResponse.json({ error: "Invalid workspace" }, { status: 400 });
  const suffix = workspace === "test" ? "TEST" : "LIVE_BETA";
  const secret = process.env[`MARKETING_AGENT_WEBHOOK_SECRET_${suffix}`];
  const address = normalizeEmailAddress(process.env[`MARKETING_AGENT_INBOUND_EMAIL_${suffix}`] ?? "");
  if (!secret || !address || !process.env.RESEND_API_KEY) return NextResponse.json({ error: "Inbox is not configured" }, { status: 503 });
  const resend = new Resend(process.env.RESEND_API_KEY);
  const payload = await request.text();
  if (payload.length > 1_000_000) return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  let event: WebhookEventPayload;
  try {
    event = resend.webhooks.verify({ payload, webhookSecret: secret, headers: {
      id: request.headers.get("svix-id") ?? "", timestamp: request.headers.get("svix-timestamp") ?? "", signature: request.headers.get("svix-signature") ?? "",
    } });
  } catch { return NextResponse.json({ error: "Invalid signature" }, { status: 401 }); }
  try {
    if (event.type === "email.received") {
      const data = event.data;
      if (![...(data.received_for ?? []), ...data.to].some(to => normalizeEmailAddress(to) === address)) return NextResponse.json({ ignored: true });
      if (isNoReplyEmail(data.from)) return NextResponse.json({ discarded: true });
      const received = await resend.emails.receiving.get(data.email_id);
      if (received.error || !received.data) throw new Error("Receiving service unavailable");
      return NextResponse.json(await receiveMarketingEmail(received.data));
    }
    if (["email.sent", "email.delivered", "email.bounced", "email.complained", "email.failed", "email.suppressed"].includes(event.type)
      && "email_id" in event.data && "from" in event.data && "subject" in event.data
      && normalizeEmailAddress(event.data.from) === MARKETING_AGENT_EMAIL && event.data.subject.includes(MARKETING_SUBJECT_TAG)) {
      await receiveDeliveryEvent(event.data.email_id, event.type, "message_id" in event.data ? event.data.message_id : undefined);
    }
    return NextResponse.json({ ok: true });
  } catch { return NextResponse.json({ error: "Processing incomplete; retry delivery" }, { status: 503 }); }
}
