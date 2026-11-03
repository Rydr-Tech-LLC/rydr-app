import "server-only";
import { marketingAgentRefs, marketingContactKey } from "./marketingAgent";
import { isNoReplyEmail, normalizeEmailAddress, MARKETING_AGENT_EMAIL, MARKETING_SUBJECT_TAG } from "./marketingAgentPolicy";

export interface IncomingMarketingEmail {
  id: string; from: string; to: string[]; subject: string; text: string | null;
  html?: string | null; headers: Record<string, string> | null; message_id: string;
}

export async function getAgentConversation(id: string) {
  if (!/^[a-f0-9]{64}$/.test(id)) throw new Error("Invalid contact.");
  const { campaign } = await marketingAgentRefs();
  const snapshot = await campaign.collection("messages").where("leadId", "==", id).limit(100).get();
  return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })).sort((a, b) => Number((a as { createdAt?: number }).createdAt) - Number((b as { createdAt?: number }).createdAt));
}

/** Called only after provider signature verification and receipt-address validation. */
export async function receiveMarketingEmail(email: IncomingMarketingEmail) {
  const { db, campaign, leads } = await marketingAgentRefs();
  const eventRef = campaign.collection("inboundEvents").doc(marketingContactKey(email.id));
  const from = normalizeEmailAddress(email.from);
  const id = marketingContactKey(from);
  const headers = Object.fromEntries(Object.entries(email.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
  const automatic = (headers["auto-submitted"] && headers["auto-submitted"].toLowerCase() !== "no")
    || /auto.?reply|out of office|automatic reply/i.test(email.subject);
  const text = (email.text ?? email.html?.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "").replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "").replace(/<[^>]*>/g, " ") ?? "[No text body]").slice(0, 40000);
  return db.runTransaction(async tx => {
    const existing = await tx.get(eventRef);
    const config = (await tx.get(campaign)).data();
    const leadRef = leads.doc(id), contactRef = db.collection("marketingAgentContacts").doc(id);
    const lead = (await tx.get(leadRef)).data();
    const suppression = (await tx.get(contactRef)).data();
    if (existing.exists) return { duplicate: true };
    const ignored = !from || isNoReplyEmail(from) || from === MARKETING_AGENT_EMAIL;
    if (!ignored && config?.inboxProbeSubject === email.subject && config.inboxProbeExpiresAt > Date.now()) {
      tx.update(campaign, { inboxVerifiedAt: Date.now(), inboxProbeSubject: null, inboxProbeExpiresAt: 0 });
      tx.create(eventRef, { outcome: "connection_verified", createdAt: Date.now() });
      return { verified: true };
    }
    if (ignored || !lead || !email.subject.includes(MARKETING_SUBJECT_TAG)) {
      // Do not store unrelated mailbox content or no-reply messages.
      tx.create(eventRef, { outcome: "discarded", createdAt: Date.now() });
      return { discarded: true };
    }
    if (automatic) {
      tx.create(eventRef, { outcome: "discarded", createdAt: Date.now() });
      tx.update(leadRef, { state: "blocked", nextFollowUpAt: null, reason: "Automatic response received; follow-ups stopped", updatedAt: Date.now() });
      tx.set(contactRef, { blocked: true, reason: suppression?.blocked ? suppression.reason : "automatic_response", updatedAt: Date.now() }, { merge: true });
      return { discarded: true };
    }
    const messageId = email.message_id && /^<[^\s<>]+>$/.test(email.message_id) ? email.message_id : "";
    const optedOut = /\bunsubscribe\b|\bremove me\b|\bstop (emailing|contacting|sending)\b|\bdo not contact\b/i.test(text.split(/\nOn .*wrote:|\n>/)[0]);
    const hardSuppressed = suppression?.blocked && !["reply_received", "replied"].includes(suppression.reason);
    tx.create(campaign.collection("messages").doc(`in-${marketingContactKey(email.id)}`), { leadId: id, direction: "inbound", kind: "reply", status: "received",
      from, subject: email.subject.slice(0, 250), body: text, messageId, providerMessageId: email.id, createdAt: Date.now() });
    tx.create(eventRef, { outcome: "reply", leadId: id, createdAt: Date.now() });
    tx.update(leadRef, { state: optedOut || hardSuppressed ? "blocked" : "replied", nextFollowUpAt: null, lastReplyAt: Date.now(),
      lastInboundMessageId: messageId, replyPreview: text.slice(0, 300), updatedAt: Date.now(),
      reason: optedOut ? "Opt-out received by email" : hardSuppressed ? lead.reason ?? "Suppressed" : "Reply received in Mission Control" });
    tx.set(contactRef, { blocked: true, reason: hardSuppressed ? suppression.reason : optedOut ? "unsubscribe" : "reply_received", updatedAt: Date.now() }, { merge: true });
    return { received: true };
  });
}

export async function receiveDeliveryEvent(providerId: string, type: string, messageId?: string) {
  const { db, campaign, leads } = await marketingAgentRefs();
  const indexRef = db.collection("marketingAgentDeliveryIndex").doc(providerId);
  return db.runTransaction(async tx => {
    const index = (await tx.get(indexRef)).data();
    if (!index) throw new Error("Delivery is not recorded yet; retry this webhook.");
    if (index.reportId) {
      tx.update(campaign.collection("shiftReports").doc(index.reportId), { deliveryEvent: type, deliveryEventAt: Date.now() });
      return;
    }
    const leadRef = leads.doc(index.leadId), contactRef = db.collection("marketingAgentContacts").doc(index.leadId);
    const lead = (await tx.get(leadRef)).data();
    if (!lead) return;
    if (["email.bounced", "email.complained", "email.failed", "email.suppressed"].includes(type)) {
      tx.update(leadRef, { state: "blocked", nextFollowUpAt: null, reason: type, updatedAt: Date.now() });
      tx.set(contactRef, { blocked: true, reason: type, updatedAt: Date.now() }, { merge: true });
    } else if (messageId && /^<[^\s<>]+>$/.test(messageId)) {
      tx.update(campaign.collection("messages").doc(index.messageId), { messageId, deliveryEvent: type });
      if (lead.providerMessageId === providerId) tx.update(leadRef, { lastMessageId: messageId });
    }
  });
}
