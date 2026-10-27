import { easternDay, withinSendingHours } from './marketingAgentPolicy';
export { easternDay, withinSendingHours };
export const ROWEN_VOICE = 'You are Rowen, Rydr Tech LLC’s AI marketing assistant working on behalf of Khris Nunnally. Warm, curious, clear and lightly upbeat. A helpful campus connector: short sentences, practical next steps, no hype, no slang overload. Never pretend to be human or Khris.';
export type SocialConfig = { active: boolean; facts: string; endsAt: number; autoReplies: boolean; dailyPosts: number; dailyReplies: number };
export function socialOpen(config: SocialConfig | undefined, now = Date.now()) {
  return Boolean(config?.active && now < config.endsAt && withinSendingHours(new Date(now)));
}
export function replyWindow(lastInboundAt: number, now = Date.now()) {
  return Number.isFinite(lastInboundAt) && lastInboundAt <= now && now < lastInboundAt + 24 * 3600000 - 60000;
}
export function publicMediaUrl(value: unknown) {
  const url = new URL(String(value));
  // Never fetch arbitrary media on the application server. Meta fetches the approved public URL.
  if (url.protocol !== 'https:' || url.username || url.password || url.port || !url.hostname.includes('.') ||
      /(^|\.)(localhost|local|internal|test)$/.test(url.hostname) || /^[\d.]+$/.test(url.hostname) || url.hostname.includes(':')) throw new Error('Use a public HTTPS media URL.');
  if (url.toString().length > 2000) throw new Error('Media URL is too long.');
  return url.toString();
}
export function cleanCaption(value: unknown) {
  const text = String(value ?? '').trim();
  if (!text || text.length > 2200) throw new Error('Enter a caption of 1–2,200 characters.');
  return text;
}
export function needsHuman(text: string) {
  return /\b(stop|unsubscribe|opt.?out|human|person|complaint|refund|accident|injur|emergency|harass|assault|suicid|payment|password|verification code|legal)\b/i.test(text);
}
export function optedOut(text: string) { return /\b(stop|unsubscribe|opt.?out|do not contact|don't contact)\b/i.test(text); }
export function normalizeSocialConfig(input: Record<string, unknown>): SocialConfig {
  const facts = String(input.facts ?? '').trim();
  const endsAt = Number(input.endsAt);
  const dailyPosts = Number(input.dailyPosts), dailyReplies = Number(input.dailyReplies);
  if (facts.length < 30 || facts.length > 6000) throw new Error('Add 30–6,000 characters of approved campaign facts.');
  if (!Number.isFinite(endsAt) || endsAt <= Date.now()) throw new Error('Choose a future campaign end.');
  if (!Number.isInteger(dailyPosts) || dailyPosts < 1 || dailyPosts > 10 || !Number.isInteger(dailyReplies) || dailyReplies < 1 || dailyReplies > 100) throw new Error('Use 1–10 posts and 1–100 replies per day.');
  return { active: input.active === true, facts, endsAt, autoReplies: input.autoReplies === true, dailyPosts, dailyReplies };
}
export function metricValue(data: any, name: string): number | null {
  const metric = data?.data?.find((m: any) => m.name === name);
  const value = metric?.total_value?.value ?? metric?.values?.at(-1)?.value;
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}
