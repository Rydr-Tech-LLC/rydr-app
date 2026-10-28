const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const crypto = require('node:crypto');
const ts = require('typescript');

const RealDate = Date;
let now = RealDate.parse('2026-10-27T16:00:00Z');
global.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : [now])); }
  static now() { return now; }
};
const docs = new Map();
let serial = Promise.resolve(), workspace = 'live-beta', sent = [], discoveryCalls = 0, copyCalls = 0;
let providerResult = { ok: true, providerMessageId: 'email-id' }, onDraft = null;
const resendCalls = [];
const copy = data => data == null ? data : structuredClone(data);
function snapshot(path) { return { id: path.split('/').at(-1), ref: doc(path), exists: docs.has(path), data: () => copy(docs.get(path)) }; }
function doc(path) {
  return { path, id: path.split('/').at(-1), get: async () => snapshot(path),
    collection: name => collection(`${path}/${name}`),
    set: async (data, options) => docs.set(path, options?.merge ? { ...docs.get(path), ...copy(data) } : copy(data)),
    update: async data => { assert(docs.has(path)); docs.set(path, { ...docs.get(path), ...copy(data) }); } };
}
function collection(path, filters = [], max = Infinity) {
  return { path, doc: id => doc(`${path}/${id}`),
    where: (name, op, value) => collection(path, [...filters, [name, op, value]], max),
    limit: limit => collection(path, filters, limit), orderBy: () => collection(path, filters, max),
    get: async () => ({ docs: [...docs.keys()].filter(p => p.startsWith(path + '/') && !p.slice(path.length + 1).includes('/'))
      .filter(p => filters.every(([name, op, value]) => { const v = docs.get(p)[name]; return op === 'in' ? value.includes(v) : op === '>' ? v != null && v > value : op === '>=' ? v != null && v >= value : op === '<' ? v != null && v < value : op === '<=' ? v != null && v <= value : v === value; }))
      .slice(0, max).map(snapshot) }) };
}
const db = { collection, runTransaction: callback => {
  const result = serial.then(async () => {
    let writing = false; const writes = [];
    const value = await callback({
      get: async ref => { assert.equal(writing, false, 'Firestore reads must precede writes'); return ref.get(); },
      set: (ref, data, options) => { writing = true; writes.push(() => ref.set(data, options)); },
      create: (ref, data) => { writing = true; writes.push(() => { assert(!docs.has(ref.path)); return ref.set(data); }); },
      update: (ref, data) => { writing = true; writes.push(() => ref.update(data)); }
    });
    for (const write of writes) await write();
    return value;
  });
  serial = result.catch(() => {}); return result;
} };
const lead = { name: 'Student Coding Club', campusName: 'Example University', category: 'student organization', kind: 'club',
  publicEmail: 'club@example.edu', sourceUrl: 'https://example.edu/clubs/coding', relevanceScore: 90, description: 'A student club' };
let discovered = [];
const originalLoad = Module._load;
Module._load = function(id, parent, ...rest) {
  if (id === 'server-only') return {};
  if (parent?.filename.endsWith('EmailService.ts')) {
    if (id === '@/lib/workspace') return { currentWorkspace: async () => workspace };
    if (id === 'resend') return { Resend: class { emails = { send: async (...args) => { resendCalls.push(args); return { data: { id: 'provider-id' } }; } }; } };
  }
  if (parent?.filename.endsWith('marketingAgent.ts') || parent?.filename.endsWith('marketingShiftReport.ts')) {
    if (id === './firebaseAdmin') return { getWorkspaceDb: async () => db };
    if (id === './workspace') return { currentWorkspace: async () => workspace };
    if (id === './ai/campusGrowthAI') return { discoveryFingerprint: () => 'existing-discovery', discoverCampusLeads: async input => {
      discoveryCalls++; assert.deepEqual(input.manualUrls, []); assert.equal(input.strategyLimit, 4);
      return { leads: discovered, warnings: [], searchResults: discovered.map(l => ({ link: l.sourceUrl, title: l.name, snippet: `Contact ${l.publicEmail}` })) };
    } };
    if (id === './ai/marketingCopy') return { draftMarketingCopy: async () => { copyCalls++; if (onDraft) await onDraft(); return { suitable: true, subject: 'Student Live Beta pilot', body: 'Would your group like to discuss a pilot?', instagramDraft: 'DM draft', reason: 'Student group', model: 'fake' }; } };
    if (id.includes('NotificationService')) return { notificationService: { sendGenericEmail: async input => { sent.push(input); return providerResult; } } };
  }
  return originalLoad.call(this, id, parent, ...rest);
};
require.extensions['.ts'] = (mod, filename) => mod._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true } }).outputText, filename);
const policy = require('../lib/marketingAgentPolicy.ts');
const agent = require('../lib/marketingAgent.ts');
const inbox = require('../lib/marketingAgentInbox.ts');
const shiftReports = require('../lib/marketingShiftReport.ts');
const campaignPath = 'marketingAgentCampaigns/student-beta-october-2026';
const leadId = email => crypto.createHash('sha256').update(email).digest('hex');
const leadPath = email => `${campaignPath}/leads/${leadId(email)}`;
const actor = { uid: 'admin', email: 'khris.nunnally@rydr-go.com' };
function config(overrides = {}) { return { name: 'Rowen', status: 'active', mode: 'automatic', startsAt: '2026-10-27T04:00:00Z', endsAt: policy.PILOT_END,
  campuses: ['Example University'], facts: 'Invite student groups to discuss a Live Beta at their school.', postalAddress: 'Test address', dailyLimit: 10, totalLimit: 50,
  dayReserved: 0, totalReserved: 0, lastDiscoveryAt: now, ...overrides }; }
function seed(email = lead.publicEmail, state = 'queued') { docs.set(leadPath(email), { ...lead, email, publicEmail: email, state, updatedAt: now, subject: 'Pilot invitation', body: 'Hello' }); }
beforeEach(() => {
  delete process.env.MARKETING_AGENT_REPORT_DATE; delete process.env.MARKETING_AGENT_REPORT_TO;
  docs.clear(); sent = []; discovered = []; discoveryCalls = 0; copyCalls = 0; workspace = 'live-beta'; onDraft = null;
  providerResult = { ok: true, providerMessageId: 'email-id' }; now = RealDate.parse('2026-10-27T16:00:00Z');
  Object.assign(process.env, { OPENAI_API_KEY: 'fake', BRAVE_SEARCH_API_KEY: 'fake', RESEND_API_KEY: 'fake', MARKETING_AGENT_SECRET: 'unit-test-only', MARKETING_AGENT_PUBLIC_URL: 'https://mc.example.com' });
  docs.set(campaignPath, config());
});

test('cloud report sends once under concurrency, after shift, without using outreach counters', async () => {
  process.env.MARKETING_AGENT_REPORT_DATE = '2026-10-27';
  process.env.MARKETING_AGENT_REPORT_TO = 'khris.nunnally@rydr-go.com';
  assert.equal((await shiftReports.sendDueShiftReport()).skipped, true);
  now = RealDate.parse('2026-10-27T21:37:00Z');
  await Promise.all([shiftReports.sendDueShiftReport(), shiftReports.sendDueShiftReport()]);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'khris.nunnally@rydr-go.com');
  assert.match(sent[0].subject, /Rowen shift report/);
  assert.equal(docs.get(campaignPath).totalReserved, 0);
  assert.equal(docs.get(campaignPath + '/shiftReports/2026-10-27').status, 'sent');
  await inbox.receiveDeliveryEvent('email-id', 'email.delivered');
  assert.equal(docs.get(campaignPath + '/shiftReports/2026-10-27').deliveryEvent, 'email.delivered');
  await shiftReports.sendDueShiftReport(); assert.equal(sent.length, 1);
});

test('ambiguous report delivery remains held and is never blindly retried', async () => {
  Object.assign(process.env, { MARKETING_AGENT_REPORT_DATE: '2026-10-27', MARKETING_AGENT_REPORT_TO: 'khris.nunnally@rydr-go.com' });
  now = RealDate.parse('2026-10-27T21:37:00Z'); providerResult = { ok:false, error:'timeout' };
  await assert.rejects(shiftReports.sendDueShiftReport());
  await shiftReports.sendDueShiftReport(); assert.equal(sent.length, 1);
  assert.equal(docs.get(campaignPath + '/shiftReports/2026-10-27').status, 'unknown');
});

test('initial deadline is November 1 Eastern and campaign can be extended', () => {
  assert.equal(policy.campaignOpen(config(), new RealDate('2026-11-01T03:59:59Z')), true);
  assert.equal(policy.campaignOpen(config(), new RealDate('2026-11-01T04:00:00Z')), false);
  assert.equal(policy.normalizeAgentConfig(config({ endsAt: '2026-11-02T05:00:00Z' })).endsAt, '2026-11-02T05:00:00.000Z');
  assert.throws(() => policy.normalizeAgentConfig(config({ dailyLimit: 1.2 })));
  assert.throws(() => policy.normalizeAgentConfig(config({ totalLimit: 0 })));
});
test('Eastern sending window boundaries are enforced', () => {
  assert.equal(policy.withinSendingHours(new RealDate('2026-10-27T12:59:59Z')), false);
  assert.equal(policy.withinSendingHours(new RealDate('2026-10-27T13:00:00Z')), true);
  assert.equal(policy.withinSendingHours(new RealDate('2026-10-27T20:59:59Z')), true);
  assert.equal(policy.withinSendingHours(new RealDate('2026-10-27T21:00:00Z')), false);
  assert.equal(policy.withinSendingHours(new RealDate('2026-10-31T16:00:00Z')), false);
  assert.equal(policy.withinSendingHours(new RealDate('2026-11-01T16:00:00Z')), false);
  assert.equal(policy.withinSendingHours(new RealDate('2026-11-02T13:59:59Z')), false);
  assert.equal(policy.withinSendingHours(new RealDate('2026-11-02T14:00:00Z')), true);
  assert.equal(policy.withinSendingHours(new RealDate('2026-11-02T22:00:00Z')), false);
});
test('qualifies public student group emails and rejects deans, guessed addresses and social-only sources', () => {
  assert.equal(policy.leadExclusion(lead, config().campuses, 'club@example.edu'), null);
  assert.match(policy.leadExclusion({ ...lead, publicContactTitle: 'Dean of Student Life' }, config().campuses, 'club@example.edu'), /administration/);
  assert.match(policy.leadExclusion({ ...lead, publicEmail: 'deanofstudents@example.edu' }, config().campuses, 'deanofstudents@example.edu'), /administration/);
  assert.match(policy.leadExclusion(lead, config().campuses, 'otherclub@example.edu'), /evidence/);
  assert.match(policy.leadExclusion({ ...lead, sourceUrl: 'https://instagram.com/club' }, config().campuses, 'club@example.edu'), /official/);
  assert.match(policy.leadExclusion({ ...lead, kind: 'event' }, config().campuses, 'club@example.edu'), /audience/);
});
test('concurrent runs send each contact once with a stable idempotency key', async () => {
  seed(); await Promise.all([agent.runMarketingAgent(), agent.runMarketingAgent()]);
  assert.equal(sent.length, 1); assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'sent');
  assert.match(sent[0].idempotencyKey, /marketing\/live-beta\//);
  assert.match(sent[0].body, /AI campus outreach assistant/); assert.match(sent[0].body, /unsubscribe/);
  assert.equal(sent[0].from, 'Rowen | Rydr Tech LLC <marketing@rydr-go.com>');
  assert.equal(sent[0].replyTo, "support@rydr-go.com"); assert.equal(sent[0].bcc, actor.email); assert.equal(docs.get(campaignPath).totalReserved, 1);
});
test('review mode does not send until explicit approval and a subsequent run', async () => {
  docs.set(campaignPath, config({ mode: 'review' })); seed(); await agent.runMarketingAgent();
  assert.equal(sent.length, 0); assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'review');
  await agent.actOnAgentLead(leadId(lead.publicEmail), 'approve', actor); now += 65_000;
  await agent.runMarketingAgent(); assert.equal(sent.length, 1);
});
test('daily and total caps survive repeated runs', async () => {
  docs.set(campaignPath, config({ dailyLimit: 1, totalLimit: 1 })); seed(); seed('second@example.edu');
  await agent.runMarketingAgent(); now += 86_400_000; await agent.runMarketingAgent();
  assert.equal(sent.length, 1); assert.equal(docs.get(campaignPath).totalReserved, 1);
});
test('pausing during AI drafting prevents sending', async () => {
  seed(); onDraft = async () => { await agent.setAgentStatus('paused', actor); };
  await agent.runMarketingAgent(); assert.equal(sent.length, 0);
});
test('deadline passing during drafting prevents sending', async () => {
  seed(); onDraft = async () => { now = RealDate.parse(policy.PILOT_END); };
  await agent.runMarketingAgent(); assert.equal(sent.length, 0);
});
test('uncertain delivery is recorded and never automatically retried', async () => {
  seed(); providerResult = { ok: false, error: 'Network outcome unknown' };
  await agent.runMarketingAgent(); now += 2 * 86_400_000; await agent.runMarketingAgent();
  assert.equal(sent.length, 1); assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'unknown');
});
test('valid unsubscribe prevents queued sending; tampered and cross-workspace links fail', async () => {
  seed(); const token = agent.unsubscribeToken(leadId(lead.publicEmail), 'live-beta');
  await assert.rejects(agent.unsubscribe(token.slice(0, -1) + (token.endsWith('0') ? '1' : '0')));
  workspace = 'test'; await assert.rejects(agent.unsubscribe(token)); workspace = 'live-beta';
  await agent.unsubscribe(token); await agent.runMarketingAgent(); assert.equal(sent.length, 0);
});
test('manual Instagram contact and historical email sends suppress queued email', async () => {
  seed(lead.publicEmail, 'ready'); await agent.actOnAgentLead(leadId(lead.publicEmail), 'instagram_sent', actor);
  seed('prior@example.edu'); docs.set('campusOutreachDrafts/old', { recipientEmail: 'prior@example.edu', status: 'sent' });
  await agent.runMarketingAgent(); assert.equal(sent.length, 0);
});
test('discovery rejects previously denied leads and does not scrape manual URLs', async () => {
  docs.set(campaignPath, config({ lastDiscoveryAt: 0 })); discovered = [lead];
  docs.set('campusDiscoveredLeads/existing-discovery', { reviewStatus: 'rejected' });
  await agent.runMarketingAgent(); assert.equal(discoveryCalls, 1); assert.equal(sent.length, 0); assert(!docs.has(leadPath(lead.publicEmail)));
});
test('test runs distinguish simulated delivery from live sends', async () => {
  workspace = 'test'; seed(); providerResult = { ok: true, providerMessageId: 'simulated-test-email' };
  const report = await agent.runMarketingAgent(); assert.equal(report.sent, 0); assert.equal(report.simulated, 1);
  assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'simulated');
});
test('settings cannot be silently rewritten after the worker starts', async () => {
  seed(); await agent.runMarketingAgent(); await assert.rejects(agent.saveAgent(config(), actor), /locked/);
});
test('expired and paused campaigns perform no discovery or drafting', async () => {
  docs.set(campaignPath, config({ status: 'paused', lastDiscoveryAt: 0 })); seed(); await agent.runMarketingAgent();
  docs.set(campaignPath, config({ lastDiscoveryAt: 0 })); now = RealDate.parse(policy.PILOT_END); await agent.runMarketingAgent();
  assert.equal(discoveryCalls, 0); assert.equal(copyCalls, 0); assert.equal(sent.length, 0);
});
test('actual EmailService bypasses Resend in Test and forwards idempotency and reply-to in Live Beta', async () => {
  const { EmailService } = require('../src/services/notifications/EmailService.ts');
  const service = new EmailService({ apiKey: 'fake', fromEmail: 'support@example.com' });
  const input = { to: 'club@example.edu', subject: 'Pilot', html: '<p>Invite</p>', replyTo: 'khris@example.com', idempotencyKey: 'stable-key' };
  workspace = 'test'; const simulated = await service.sendEmail(input);
  assert.equal(simulated.id, 'simulated-test-email'); assert.equal(resendCalls.length, 0);
  workspace = 'live-beta'; await service.sendEmail(input);
  assert.equal(resendCalls.length, 1); assert.equal(resendCalls[0][0].replyTo, input.replyTo);
  assert.equal(resendCalls[0][1].idempotencyKey, 'stable-key');
});

test('off-shift invocations do no research, drafting or sending', async () => {
  docs.set(campaignPath, config({ lastDiscoveryAt: 0 })); seed();
  for (const instant of ['2026-10-27T12:59:59Z', '2026-10-27T21:00:00Z', '2026-10-31T16:00:00Z']) {
    now = RealDate.parse(instant); const result = await agent.runMarketingAgent(); assert.equal(result.skipped, true);
  }
  assert.equal(discoveryCalls, 0); assert.equal(copyCalls, 0); assert.equal(sent.length, 0);
});
test('shift ending during drafting prevents delivery', async () => {
  seed(); onDraft = async () => { now = RealDate.parse('2026-10-27T21:00:00Z'); };
  await agent.runMarketingAgent(); assert.equal(sent.length, 0);
});
test('schedule extension preserves counters and converts Eastern time after DST', async () => {
  docs.set(campaignPath, config({ firstRunAt: now, totalReserved: 7 }));
  await agent.updateAgentSchedule({ endsLocal: '2026-11-10T00:00', dailyLimit: 10, totalLimit: 100, maxFollowUps: 2, followUpDays: 3 }, actor);
  const saved = docs.get(campaignPath); assert.equal(saved.endsAt, '2026-11-10T05:00:00.000Z'); assert.equal(saved.totalReserved, 7); assert.equal(saved.status, 'active');
});
function incoming(overrides = {}) { return { id: 'incoming-1', from: lead.publicEmail, to: ['inbox@example.com'], subject: '[Rydr Campus] Pilot invitation', text: 'Yes, tell us more.', headers: {}, message_id: '<reply@example.edu>', ...overrides }; }
test('follow-ups wait for verified reply connection, then send once when due', async () => {
  seed(); await agent.runMarketingAgent(); now += 3 * 86400000;
  await agent.runMarketingAgent(); assert.equal(sent.length, 1);
  docs.get(campaignPath).inboxVerifiedAt = now; now += 65000;
  await agent.runMarketingAgent(); assert.equal(sent.length, 2); assert.equal(docs.get(leadPath(lead.publicEmail)).followUpsSent, 1);
  now += 65000; await agent.runMarketingAgent(); assert.equal(sent.length, 2);
});
test('received replies are deduplicated and stop automatic follow-ups', async () => {
  seed(); await agent.runMarketingAgent(); docs.get(campaignPath).inboxVerifiedAt = now;
  await inbox.receiveMarketingEmail(incoming()); assert.equal((await inbox.receiveMarketingEmail(incoming())).duplicate, true);
  now += 3 * 86400000; await agent.runMarketingAgent(); assert.equal(sent.length, 1); assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'replied');
  assert.equal((await inbox.getAgentConversation(leadId(lead.publicEmail))).filter(m => m.direction === 'inbound').length, 1);
});
test('Mission Control replies use threading and stable operation IDs', async () => {
  seed(); await agent.runMarketingAgent(); await inbox.receiveMarketingEmail(incoming());
  const input = { kind: 'reply', subject: 'Pilot', body: 'Thank you for your interest.', operationId: crypto.randomUUID(), actor: actor.email };
  await agent.sendAgentMessage(leadId(lead.publicEmail), input); await agent.sendAgentMessage(leadId(lead.publicEmail), input);
  assert.equal(sent.length, 2); assert.equal(sent[1].headers['In-Reply-To'], '<reply@example.edu>'); assert.equal(sent[1].bcc, actor.email);
});
test('email opt-outs cannot be bypassed by marking a lead replied', async () => {
  seed(); await agent.runMarketingAgent(); await inbox.receiveMarketingEmail(incoming({ text: 'Please unsubscribe me.' }));
  assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'blocked');
  await assert.rejects(agent.actOnAgentLead(leadId(lead.publicEmail), 'replied', actor), /suppressed/);
});
test('noreply inbound bodies are discarded and noreply outreach is blocked', async () => {
  const result = await inbox.receiveMarketingEmail(incoming({ from: 'No Reply <no-reply@example.edu>', text: 'PRIVATE AUTOMATIC BODY' }));
  assert.equal(result.discarded, true); assert(!JSON.stringify([...docs.values()]).includes('PRIVATE AUTOMATIC BODY'));
  seed('no_reply@example.edu'); await agent.runMarketingAgent(); assert.equal(sent.length, 0);
});
test('automatic replies stop follow-ups without retaining their content', async () => {
  seed(); await agent.runMarketingAgent(); await inbox.receiveMarketingEmail(incoming({ headers: { 'Auto-Submitted': 'auto-replied' }, text: 'AUTOMATIC PRIVATE BODY' }));
  assert.equal(docs.get(leadPath(lead.publicEmail)).state, 'blocked'); assert(!JSON.stringify([...docs.values()]).includes('AUTOMATIC PRIVATE BODY'));
});
test('inbox probe verifies forwarding only for the current unexpired subject', async () => {
  const subject = await agent.createInboxProbe();
  assert.equal((await inbox.receiveMarketingEmail(incoming({ subject, from: actor.email }))).verified, true);
  assert.equal(docs.get(campaignPath).inboxVerifiedAt, now);
});
test('shift analytics distinguish sent, simulated, received and excluded work', async () => {
  seed(); await agent.runMarketingAgent(); await inbox.receiveMarketingEmail(incoming());
  const snapshot = await agent.agentSnapshot(); assert.equal(snapshot.shift.outreach, 1); assert.equal(snapshot.shift.replies, 1); assert.equal(snapshot.shift.drafted, 1); assert.equal(snapshot.shift.simulated, 0); assert.equal(snapshot.shift.batches, 1);
  now = RealDate.parse('2026-10-28T16:00:00Z'); const next = await agent.agentSnapshot(); assert.equal(next.shift.outreach, 0); assert.equal(next.shift.replies, 0);
});
