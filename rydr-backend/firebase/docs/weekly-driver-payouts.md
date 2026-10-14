# Weekly driver ACH payouts

Schedule: Mondays, 09:00 America/New_York (DST-aware). Initiation is not the bank
arrival date. No iOS changes or release are required. The existing instant
cash-out request/response schema and Stripe idempotency namespace are preserved.

## Architecture

`queueMondayDriverPayouts` pages through drivers and creates deterministic jobs
in `driverPayouts` for each Connect account/week. Approved drivers without an
account receive an issue. Onboarding drivers without accounts are skipped.
`dispatchWeeklyDriverPayout` sends the job ID to the existing Stripe backend
using `RYDR_INTERNAL_SERVICE_TOKEN`. Caller-provided amounts and destinations
are never accepted. The backend rechecks Connect ownership and eligibility,
reads Stripe's available USD balance, ignores pending funds, and pays to a valid
US USD default bank account using `method: standard`. It never falls back to a
debit card. Distinct balance source types have distinct stable payout keys.

New Express accounts use a manual payout interval. Existing accounts must be
prepared with `/internal/payout-policy/prepare` before activation; this changes
payout timing without initiating a payout. Stripe's automatic daily schedule
must not continue draining funds intended for weekly payout. Both app-initiated
instant payouts and weekly jobs acquire the same persistent Connect-account
lock. Bank failures, disabled payouts, missing banks/accounts, dispatch errors,
and uncertain responses are flagged in Mission Control's `/payouts` queue.

Payout payloads are saved before Stripe invocation. A connection error or an
uncertain result retains the account lock; there is no blind resubmission even
after Stripe's idempotency retention expires. Definite API rejection releases
the lock. Weekly unknown responses can be discovered by payout metadata. Known
instant payouts are mapped to their job in `driverPayoutStripeLinks`; their API
metadata remains identical to the shipped endpoint to keep existing Stripe
idempotent retries compatible. An instant response lost before recording its
Stripe ID may require Stripe Dashboard investigation; it is never guessed by
matching amount alone. Unresolved locks remain blocked pending a known outcome.

Signed Connect payout webhooks fetch current Stripe status before updating the
ledger, preventing stale events from regressing state. `reconcileDriverPayouts`
also refreshes processing/pending/review jobs every 30 minutes using cursors.
Reconciliation never creates a payout. The UI's Recheck action reads payout
state (or repairs the manual interval for a policy issue) and records an audit.

## Deployment order

1. Deploy `rydr-backend/services/stripe` to the existing Render Stripe service.
2. Confirm the internal payout endpoints reject unauthenticated requests with
   401 and that the deployed revision matches the tested source.
3. Using the existing internal service token, page through
   `POST /internal/payout-policy/prepare` (`{cursor}`; first call `{}`) until
   `nextCursor` is null. Review setup failures. This moves no money.
4. If a connected-account Stripe webhook is configured, include
   `payout.created`, `payout.updated`, `payout.paid`, `payout.failed`, and
   `payout.canceled`. The background reconciler covers new tracked payouts
   even when webhook events are delayed or not yet subscribed.
5. Deploy Firebase Functions `queueMondayDriverPayouts`,
   `dispatchWeeklyDriverPayout`, and `reconcileDriverPayouts` with the existing
   secret `RYDR_INTERNAL_SERVICE_TOKEN` and `RYDR_STRIPE_BACKEND_URL`.
6. Deploy Mission Control with its existing Firebase credentials and
   `RYDR_INTERNAL_SERVICE_TOKEN`. `STRIPE_BACKEND_BASE_URL` optionally overrides
   the existing Render Stripe service URL.

No live payout is initiated as part of validation. Unit/integration tests use
fake Stripe/Firestore services and check settled balances, source splits,
concurrency, duplicate retries, lost responses, ownership changes, bank errors,
webhook ordering, interruption handling, and policy setup. The schedule test
covers Eastern dates and DST. App payout history remains backed by Stripe.

Queued jobs outside the current Eastern calendar week are flagged rather than
withdrawing a later week’s balance. Dispatch retries within the scheduled week
can initiate late if the backend was unavailable on Monday.

## Activated October 14, 2026

Render runs payout revision `94a7652`. Auto-Deploy is disabled with the owner's
approval until the branch is merged. Mission Control's payout queue and all
three Firebase functions are deployed. Cloud Scheduler confirms the next weekly
run is October 19, 2026, at 09:00 America/New_York. Status reconciliation runs
every 30 minutes. Account preparation scanned 12 drivers: none had a linked
Stripe Connect account, so no existing Stripe payout interval was changed.

The current live Stripe webhook receives platform-account events, not Connect
events. New driver payout status and failure detection therefore use the
30-minute reconciler. Immediate Connect event delivery can be added separately
with a connected-account webhook; it is not required for the deployed flow.
