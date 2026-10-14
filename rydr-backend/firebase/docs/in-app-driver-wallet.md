# Driver wallet and payout account management

Rydr owns the driver navigation, earnings UI, and payout controls. Stripe confirms
balances and bank movement and collects sensitive account information through
Connect embedded components inside the app. Bank/card management no longer opens
an Express dashboard login link. Signup uses native Connect embedded onboarding.
Express-required authentication can still appear in an in-app system web session;
the app must not suppress that verification or promise a wholly custom form.

The existing pinned Stripe iOS SDK 24.24.2 exposes the documented Payouts component
through PreviewConnect. Rydr embeds it for external account collection with
instant/standard payouts and schedule edits disabled. All withdrawals continue
through Rydr's persistent shared payout lock. Initial setup uses public embedded
onboarding and completion is checked through the backend. A session can access
only the authenticated driver's server-owned Connect account. Client-supplied
account IDs are not trusted. Sessions are scoped to one purpose, expire, are not
cached or logged, and retain Stripe authentication for Express accounts. Backend
secret/publishable mode mismatch prevents loading. Stripe test mode is retained.

`GET /connect/wallet` returns USD settled balance, pending settlement, actual
instant eligibility/destination, payouts in transit, verification state, linked
account summaries, and cursor-paginated history. Pending settlement is not a
bank payout. Historical destinations and fees are derived from each Stripe
payout's expanded destination and balance transaction, not the driver's current
bank or an assumed percentage. Unknown fees remain unknown. Balance refresh
failures hide the cash-out amount and disable new withdrawals.

New instant requests name the eligible destination and use a v2 idempotency key.
Eligibility is checked again under the same lock used by weekly payouts. Shipped
clients retain their old payload and idempotency key. An uncertain mobile
response retains the request ID/payload for retry; server-side locks survive app
restarts. A definite pre-submission failure may clear the client request. Unknown
outcomes remain flagged for Mission Control review. Do not test by moving live
funds. Device testing still needs an authenticated test Connect account to cover
bank/card forms, verification prompts, canceled forms, and refreshed summaries.

Release requires the updated Stripe backend routes plus a new Rydr Driver build.
No rider app changes, Firebase rules, or new secrets are required.
