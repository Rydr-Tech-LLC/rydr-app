const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
require.extensions['.ts'] = (mod, filename) => mod._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, filename);
const { reportWindow, summarizeShift } = require('../lib/marketingShiftReportPolicy.ts');

test('report runs only on requested Eastern date after 5:30, with daylight saving changes', () => {
  assert.equal(reportWindow(new Date('2026-10-28T21:29:59Z'), '2026-10-28').due, false);
  assert.equal(reportWindow(new Date('2026-10-28T21:30:00Z'), '2026-10-28').due, true);
  assert.equal(reportWindow(new Date('2026-10-29T21:37:00Z'), '2026-10-28').due, false);
  assert.equal(reportWindow(new Date('2026-11-02T21:37:00Z'), '2026-11-02').due, false);
  assert.equal(reportWindow(new Date('2026-11-02T22:37:00Z'), '2026-11-02').due, true);
  assert.equal(reportWindow(new Date(), '').due, false);
});

test('report counts accepted campaign sends, separates delivery, includes replies and failures', () => {
  const report = summarizeShift('2026-10-28', [
    { direction:'outbound', kind:'initial', status:'sent', sentAt:10, to:'club@example.edu', leadId:'club', deliveryEvent:'email.delivered' },
    { direction:'outbound', kind:'followup', status:'sent', sentAt:11, to:'club2@example.edu' },
    { direction:'outbound', kind:'initial', status:'simulated', sentAt:12 },
    { direction:'outbound', kind:'reply', status:'sent', sentAt:12 },
    { direction:'outbound', kind:'initial', status:'sent', sentAt:30 },
    { direction:'outbound', kind:'initial', status:'unknown', to:'club3@example.edu' },
    { direction:'inbound', from:'club@example.edu', subject:'Re: pilot' },
  ], [{ warnings:['Search incomplete'] }], [{ id:'club', name:'Coding Club', campusName:'Example University', reason:'email.bounced' }], 20);
  assert.equal(report.initial, 1); assert.equal(report.followups, 1); assert.equal(report.replies, 1);
  assert.match(report.body, /Coding Club \| Example University/);
  assert.match(report.body, /Delivery confirmed/);
  assert.match(report.body, /Provider accepted; delivery not confirmed/);
  assert.match(report.body, /Search incomplete/); assert.match(report.body, /email.bounced/);
  assert.match(report.body, /Unconfirmed send/);
});

test('missing runs are reported as an issue instead of a successful empty shift', () => {
  assert.match(summarizeShift('2026-10-28', [], [], [], 20).body, /No completed worker batches/);
});
