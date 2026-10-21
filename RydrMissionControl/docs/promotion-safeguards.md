# Promotion accounting and abuse review

The mobile app does not own eligibility, counters, earned rewards, or review overrides. Deploy the Stripe service and Mission Control together; no mobile build is needed. This change is source-only until those services are deployed.

## Configure the two launch examples

- **Pay for your first ride, receive the next ride free:** rider milestone reward; new-account audience; one qualifying paid ride; free-ride reward; one reward per account; explicit fare amount or distance cap; reward expiration. Only completed, successfully paid, undiscounted rider rides qualify. The earned reward is applied once to the next eligible completed ride, subject to the cap, market, ride class, expiration and non-stacking rules. Wait charges and other extras remain governed by the existing fare policy; advertise the offer with its cap and exclusions.
- **Next four rides at 50%:** rider fare discount; 50%; four uses per account; explicit maximum discount per ride; campaign dates; optional total campaign cap. Use new-account audience only if the offer is intended exclusively for new riders.

New-account campaigns default to one reward/use if the per-account field is blank. Other audiences retain explicit unlimited campaigns when that field is blank. An explicitly entered four-use limit overrides the new-account default.

## Durable accounting

A Firestore transaction reserves a use, increments campaign/account counters, and creates the ride's financial promotion record. All concurrent attempts contend on those records. A retry, including after a pause or account hold, reuses the original decision and amount. A `none` decision is durable too. Never delete a reservation or reset a counter merely because a network request or card charge failed: Stripe may still complete it, and its idempotency key must keep the original amount. Failed/unpaid ride reservations remain committed until their payment is resolved; they do not silently become extra uses on a different ride.

Successful direct charges and Stripe success webhooks now call the same idempotent settlement engine. The existing paid-outcome Firebase trigger is a retrying recovery path. Settlement requires both a paid financial outcome and a completed, successfully paid ride. Per-ride event markers prevent double progress, and a used reward cannot be redeemed twice. Discounted/free rider rides do not create more milestone rewards.

The old non-transactional promotion fallback has been removed. Existing schema-1 campaigns must be reviewed/recreated as schema-2 campaigns before use. Read-only inventory on October 19, 2026 found no campaigns in the production project's `live-beta` or `(default)` databases; the separate Test project was not inventoried.

## Mission Control

Promotion details show campaign commitments, account counts, remaining capacity, redemptions and reward states. Views are explicitly bounded to 100 records per category. The safeguards panel shows up to 50 pending identity signals and 50 held accounts. A hold prevents new reservations, enrollments and milestone rewards. It does not rewrite an already-committed payment amount or revoke a reward already consumed.

Every hold, release and campaign-specific review exception requires a reason and writes an audit in the same transaction. Releasing a manual hold does not clear a duplicate-identity restriction. Allowing a shared identity requires a matching stored review signal, applies to that account and campaign only, and does not override a manual hold.

## Duplicate-account evidence and limits

For new-account offers, the engine claims available verified Firebase Auth phone evidence and the Stripe customer's default card fingerprint. Stripe evidence is accepted only when customer metadata `firebase_uid` matches the authenticated account and the retrieved payment method belongs to that customer. Workspace Auth is injected by the service so Test and Live Beta remain separate. Client profile phone/device/card hints are not evidence.

Claims and counters are read/written atomically; a second account sharing evidence is held from that offer and creates a review signal. Raw phone numbers, card numbers and fingerprints are not stored in the promotion claims or exposed in Mission Control. Claims survive account deletion so recreating an account does not erase prior evidence. These server-only records require an explicit retention/privacy policy; deleting them resets that historical protection.

A match is possible abuse, not proof. Families may share a card, phone numbers may be recycled, wallet fingerprints can differ, and someone using a different verified phone and card can evade these signals. Only the default saved card is examined. This is not device fingerprinting, an IP ban, or guaranteed identity resolution. Existing accounts without shared evidence are not retroactively linked, and issued rewards are not retroactively revoked.

## Validation and rollout

Run `node --test test/promotionEngine.test.js test/promotionPolicy.test.js test/promotionRoutes.test.js` from the Stripe service; run `node --test test/promotions.test.cjs test/promotionSafety.test.cjs` and `npm run build` from Mission Control. The integrated full Stripe suite passes 131 tests. The two payout-lock fixtures now use the service’s injected clock rather than the wall clock; payout runtime behavior is unchanged.

Deploy the Stripe service from `rydr-backend/services/stripe` on Render and Mission Control on Vercel. Preserve the separate Notifications changes when assembling the deployed Mission Control source. The added Firestore rule entries explicitly deny mobile access; the existing default-deny already protects these new collections. Avoid deploying unrelated local Firestore-rule changes.

Before advertising, exercise both offers with Test accounts through real payment outcomes, retries, a fifth ride, a shared-card account, a manual hold and an audited review exception. No campaigns or financial records were created in production while implementing this change.
