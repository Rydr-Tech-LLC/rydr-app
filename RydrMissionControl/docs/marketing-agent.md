# Rowen: student Live Beta outreach pilot## Cloud first-shift reportThe existing hosted marketing worker checks for a one-time report after 5:30 p.m.Eastern. Production settings `MARKETING_AGENT_REPORT_DATE=2026-10-28` and`MARKETING_AGENT_REPORT_TO=khris.nunnally@rydr-go.com` select the requested firstshift and recipient. On October 28 the next GitHub tick is 5:37 p.m. Eastern;scheduled jobs can be delayed. The user's computer and browser are not required.The report contains accepted initial/follow-up counts, organizations, campuses,addresses, replies by report time, and recorded problems. It distinguishesprovider acceptance from confirmed delivery, excludes setup probes and simulations,and flags missing worker runs. A transactional `shiftReports/YYYY-MM-DD` documentunder the campaign stores the report and prevents duplicate sends. Delivery eventsupdate that document. Ambiguous sends require manual reconciliation. Reports donot consume outreach caps. This is one report, not daily recurring reporting;any future reporting date needs a hosted post-shift invocation after DST changes.

Open Campus Growth → Marketing Agent in Mission Control. The pilot window is
October 27, 2026 through October 31, ending **November 1 at 00:00 America/New_York**
(`2026-11-01T04:00:00Z`; daylight saving time has not ended yet). This is an initial
end date, not a permanent cutoff. Admins can extend it under Schedule & follow-ups,
including after it expires, without resetting delivery history or counters.

## What this version does

- Searches public campus organization listings via the existing Brave/OpenAI discovery service.
  It rotates the configured campuses, searching one campus every six hours with at most
  four queries per discovery run. No Firecrawl/manual URL extraction, Instagram scraping,
  private directories, personal student lists, or guessed emails.
- Requires a published organization email in retrieved evidence from an HTTPS `.edu`
  source, a selected campus, student-group relevance, and a minimum relevance score of 65.
  Excludes deans, provosts, admissions, registrars, chancellors, and unrelated individuals.
  Restrictiveness is deliberate; if search snippets omit email evidence, no email is sent.
- Drafts short invitations using the saved campaign brief. The agent identifies itself
  as an AI assistant for Rydr Tech LLC acting on behalf of Khris Nunnally.
- Automatic mode sends eligible drafts; review mode holds drafts until an admin approves.
  A scheduled or manual run then sends approved drafts during **Monday–Friday, 09:00–17:00 America/New_York**.
  Research and drafting follow the same shift; daylight saving changes are automatic.
  Defaults: 10 email reservations/day, 50 total, at most 3 contacts processed/run.
- Sends as `Rowen | Rydr Tech LLC <marketing@rydr-go.com>` (display name follows the saved agent name).
  Adds an unsubscribe link and mailing address. Reply-To is `support@rydr-go.com`;
  BCC is `khris.nunnally@rydr-go.com`. Uses existing Resend letterhead delivery.
- Prepares Instagram DM drafts for manual first contact from `@rydr_tech`.
  Only verified organization Instagram URLs are linked. Marking a DM sent suppresses
  the queued email. This build does not connect Meta, publish social posts, or auto-send DMs.

## Deployment and activation

1. Deploy the Mission Control changes with its existing Firebase workspace credentials.
   Marketing data is stored in `marketingAgentCampaigns` and `marketingAgentContacts`;
   the existing default-deny Firestore rules prevent direct client access.
2. Configure `OPENAI_API_KEY`, `BRAVE_SEARCH_API_KEY`, and `RESEND_API_KEY`, plus the
   verified sending domain for `marketing@rydr-go.com`. The agent's sender is fixed to
   this alias, independently of `CAMPUS_OUTREACH_FROM_EMAIL` used by manual outreach.
   Configure the alias with your email provider separately; changing this code does not
   create a mailbox or verify a domain in Resend. The existing `OPENAI_CAMPUS_MODEL` override is
   reused. Drafting and public search incur provider usage even in Test.
3. Set `MARKETING_AGENT_PUBLIC_URL` to the deployed HTTPS Mission Control origin.
   Generate two separate high-entropy secrets: `MARKETING_AGENT_SECRET` for unsubscribe
   signatures and `MARKETING_AGENT_RUN_SECRET` for scheduler authentication. Keep the
   unsubscribe secret stable so delivered opt-out links remain valid after the pilot.
4. In Test, save the brief, confirm campuses, activate, and run once. Test uses the
   isolated test workspace and records simulated delivery; it never emails recipients.
5. In Live Beta, review the brief and limits and enter Rydr's real mailing address.
   Save, then activate. The campaign brief locks after the first run, while end date,
   email caps, follow-up count (0–2) and spacing (2–14 days) remain editable. Pause remains
   available; saved dates and shift hours are enforced before automated delivery.
6. For unattended operation, enable the supplied GitHub Actions workflow on the default
   branch. Set repository variable `MARKETING_AGENT_PUBLIC_URL`, repository secret
   `MARKETING_AGENT_RUN_SECRET` matching the deployment, and repository variable
   `RYDR_MARKETING_AGENT_ENABLED=true`. GitHub schedules may be delayed; this is not an
   exact-time delivery SLA. Alternatively invoke the same script from your scheduler.
   The workflow has read-only repository permissions and remains inert until enabled.
7. Confirm a scheduled run in Mission Control's run history. A configured credential
   alone does not prove the scheduler is installed. Disable the repository variable
   after the campaign. The server enforces saved campaign dates. Weekday scheduled calls
   run every 15 minutes in a UTC envelope covering both Eastern time offsets; off-shift
   calls return without research, drafting, or sending.

Manual invocation: POST `/api/campus-growth/agent/run`, with
`Authorization: Bearer <MARKETING_AGENT_RUN_SECRET>` and
`x-rydr-workspace: live-beta`. Never expose this credential to client code.
The deployed runtime must support a 300-second request duration.

## Delivery and operator responsibilities

Transactions serialize worker leases, per-contact claims, opt-outs, and daily/total
reservations. Resend receives a stable idempotency key per contact/workspace/campaign.
Reservations remain counted on failure. `unknown` or stuck `sending` means delivery
needs reconciliation in Resend; the worker never retries those contacts automatically.
This avoids duplicate sends after Resend's 24-hour idempotency retention expires.

Unsubscribe GET displays a confirmation form; POST validates a signed, workspace-bound
token and immediately suppresses future agent sends. No login is required. Other manual
Campus Growth sending tools are not part of this agent's suppression mechanism.

Replies arrive in the support@rydr-go.com Gmail mailbox. Forward campaign copies into Mission Control
using the setup below. Human replies, opt-outs, bounces and complaints stop follow-ups.
Automatic replies are discarded and also stop follow-ups; no-reply sender bodies are not
stored. This does not delete originals from Gmail. Admins can view conversations and send
threaded replies from Mission Control. The agent does not autonomously negotiate or book
meetings. Messages already handed to Resend may arrive after a pause, shift end or opt-out.

## Gmail reply connection

1. Create a Resend receiving address per workspace (separate addresses and webhook
   signing secrets). Use a receiving subdomain or Resend-provided address; retain the existing mail provider’s
   existing MX records for `rydr-go.com`.
2. Set `MARKETING_AGENT_INBOUND_EMAIL_TEST` and `_LIVE_BETA` to the respective
   receiving addresses. Set `MARKETING_AGENT_WEBHOOK_SECRET_TEST` and `_LIVE_BETA`
   to the respective Resend webhook signing secrets.
3. Register `/api/campus-growth/agent/inbound/test` and
   `/api/campus-growth/agent/inbound/live-beta` as Resend webhook endpoints. Subscribe to
   email.received, email.sent, email.delivered, email.bounced, email.complained,
   email.failed and email.suppressed. The route verifies raw-body signatures and selects
   workspace from its path. Received destination addresses must match that workspace.
4. In Khris's Gmail Settings → Filters, create a rule for subject containing
   `[Rydr Campus]`, forwarding to the Live Beta receiving address and keeping the original.
   Complete Gmail destination verification using the code in Resend's receiving dashboard;
   Mission Control deliberately discards unrelated emails, including verification mail.
   Do not forward the entire mailbox. Gmail plan/admin settings may restrict forwarding.
5. Click **Check Gmail reply connection** in Mission Control. From another mailbox, send
   support@rydr-go.com an email with the exact generated subject within 30 minutes. Confirm the panel
   shows a verification timestamp. Live automatic follow-ups remain held until this passes.
6. Perform a controlled round trip before activating live outreach. Verify original
   sender preservation through Gmail forwarding, correct workspace, conversation display,
   Reply-To/BCC, threading, suppression and delivery events. No live round trip has been
   performed by the local tests. If forwarding rewrites the sender, do not enable follow-ups
   until that is resolved.

Up to two automatic follow-ups are sent, defaulting to three calendar days apart, during
the next eligible shift. Each uses its own stable outbox ID. Extending the campaign keeps
previous sends and makes still-eligible follow-ups available. Reserved sends count toward
caps even when their outcome is uncertain. Contact suppression cannot be removed by
marking a contact replied.

## Shift analytics

The existing Mission Control colors, cards and typography are reused. The panel refreshes
every 30 seconds while visible and shows current shift status, last activity, newly eligible
groups, excluded candidates, drafts, initial sends, follow-ups, inbound replies, manual
responses, simulations and run/send issues. Counts cover today's 09:00–17:00 Eastern
window; each query is capped at 1,000 records and the UI flags truncation. Sent means
provider acceptance, not confirmed delivery or engagement. Issues can count both a failed
batch and a failed message. No productivity score or quota is imposed. Batch waiting time
is normal; the eight-hour shift is an availability window, not eight hours of constant
model execution. Incoming replies are processed at any time. The contact list shows the
latest 250 contacts and conversation views up to 100 messages; analytics are independent
of that contact-list limit. Follow-up scheduling scans up to the 10,000-contact campaign
cap; revisit this approach before raising that cap.

Instagram's official Send API requires an inbound message before API-based replies.
Connecting a professional account, validating Meta webhooks, and implementing its reply
window are separate work; do not treat the DM draft UI as a connected Instagram sender.
Social content planning and approved publishing can be added as a separate module.

References: [Meta Instagram API](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api),
[Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys),
[OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs).

## Validation

Run `npm run test:marketing-agent` and `npx tsc --noEmit` in RydrMissionControl.
Tests use an in-memory transactional database and fake providers: they do not send email
or require production credentials. Validate a deployed Test run before enabling Live Beta.

Reply setup references: [Gmail forwarding](https://www.zoho.com/mail/help/email-forwarding.html), [Resend webhook verification](https://resend.com/docs/webhooks/verify-webhooks-requests), [Resend receiving](https://resend.com/docs/api-reference/emails/retrieve-received-email).
