import { NextRequest, NextResponse } from "next/server";
import { getAdminSession, getCampusGrowthSession } from "@/lib/session";
import { agentSnapshot, saveAgent, setAgentStatus, actOnAgentLead, updateAgentSchedule, createInboxProbe, sendAgentMessage } from "@/lib/marketingAgent";
import { getAgentConversation } from "@/lib/marketingAgentInbox";
import { writeAuditLog } from "@/lib/auditLog";

export async function GET(request: NextRequest) {
  if (!await getCampusGrowthSession()) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const id = request.nextUrl.searchParams.get("leadId");
  if (id) {
    if (!/^[a-f0-9]{64}$/.test(id)) return NextResponse.json({ error: "Invalid contact" }, { status: 400 });
    return NextResponse.json({ messages: await getAgentConversation(id) });
  }
  return NextResponse.json(await agentSnapshot());
}

export async function POST(request: NextRequest) {
  const actor = await getAdminSession();
  if (!actor) return NextResponse.json({ error: "An admin must manage the marketing agent." }, { status: 403 });
  const body = await request.json().catch(() => null);
  try {
    let result: object = {};
    if (body?.action === "save") await saveAgent(body.config, actor);
    else if (body?.action === "pause") await setAgentStatus("paused", actor);
    else if (body?.action === "activate") await setAgentStatus("active", actor);
    else if (body?.action === "lead") await actOnAgentLead(body.id, body.leadAction, actor);
    else if (body?.action === "schedule") await updateAgentSchedule(body, actor);
    else if (body?.action === "probe") result = { subject: await createInboxProbe() };
    else if (body?.action === "reply") {
      const sent = await sendAgentMessage(body.id, { kind: "reply", subject: body.subject, body: body.message, operationId: body.operationId, actor: actor.email ?? actor.uid });
      if (!["sent", "simulated"].includes(sent.status)) return NextResponse.json({ error: "reason" in sent ? sent.reason : "Reply was not confirmed. Check the conversation before retrying." }, { status: 409 });
      result = sent;
    }
    else return NextResponse.json({ error: "Invalid action" }, { status: 400 });
    await writeAuditLog({ adminUid: actor.uid, adminEmail: actor.email ?? undefined,
      action: `Marketing Agent ${body.action}`, targetType: "marketingAgentCampaign", targetId: "student-beta-october-2026",
      metadata: { leadId: body.id ?? null, leadAction: body.leadAction ?? null } });
    return NextResponse.json({ ok: true, ...result });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Agent action failed." }, { status: 400 });
  }
}
