# Promotion operations

Mission Control → Promotions creates rider discounts (percentage, dollar credit, or free ride within an amount/distance cap), rider ride milestones, driver per-ride bonuses, and driver ride milestones. Suggestions are editable starting points, never seeded campaigns. New promotions remain drafts until an administrator reviews and publishes them. All scheduling uses America/New_York, including daylight saving.

## Eligibility and codes

Offers apply to regular Rydr rides and can restrict audience (all, new, beta, or named Firebase account IDs), pickup market, ride type, per-account rewards and total rewards. Zero/negative/fractional usage limits are rejected; a blank limit means unlimited. A new account has no previously completed, successfully paid rides. Its first qualifying ride or validated code enrollment establishes the new-account cohort for subsequent milestone progress.

Codes are unique, uppercase, 3–32 characters, with letters, numbers, underscores or dashes. `RB-` belongs to the existing Rydr Bank system. Code ownership is reserved transactionally in `promotionCodes`. Archived campaign codes stay reserved for audit integrity. Reusing a campaign creates a draft with a blank code. Published financial/eligibility terms cannot be changed, including by moving the campaign back to draft; reuse it for new terms. Pause/resume intervals exclude rides completed while an offer was paused.

Authenticated Stripe backend endpoints:

- `POST /promotions/enroll`: `{code, audience: "riders" | "drivers"}`. Verifies the caller, active schedule and audience before creating account-wide enrollment.
- `GET /promotions/account?audience=riders|drivers`: eligible offers, own progress, earned rewards and own driver bonus activity. Code-only offers become visible after enrollment.

The rider app has **Promotions & ride rewards** in Rydr Bank. The driver Wallet has **Driver promotions & bonuses**. These new app screens require a subsequent app build; Mission Control and backend mechanics can deploy independently. This change does not upload a TestFlight build.

## Fare and funding

Only one rider promotion is selected: the largest available eligible discount. Existing Rydr Bank redemptions do not stack. Fare subtotal and booking fee qualify; tips, tolls, paid waiting and other extras do not. A distance reward covers fare in proportion to the covered miles and covers the booking fee in full. Above-limit distance/time fare remains payable; if excess trips are disabled, an over-limit trip is ineligible. Missing authoritative distance never qualifies a distance reward.

The financial outcome retains the full pre-promotion driver payout and platform share. Rydr funds the rider discount. Existing Cash Hub withholding still applies normally. A separate platform transfer fills any gap between the rider payment and the normal driver transfer. Driver bonus promotions add a separate cash transfer to the driver's Connect balance; weekly ACH and instant cash-out keep their existing policy.

Reservations atomically consume campaign/user capacity and lock the selected discount per ride. Failed payments retain that reservation so retries cannot change the idempotent payment amount or consume a reward twice. Available earned rewards expire after the configured number of days; rewards already reserved for a ride remain locked to that ride. Earned rider rewards remain usable after campaign end, within the earned reward's own original restrictions and expiration.

## Milestones and issues

The paid financial outcome dispatches reward settlement through `onPaidRidePromotionSettlement`. Only completed, successfully settled rides count. Duplicate callbacks do not count twice. Discounted/free rides do not advance rider milestones; driver promotions may count Rydr-funded rides. Milestone capacity is consumed when the reward is issued, not again on its later redemption.

Driver bonus and promotion subsidy transfers have permanent dispatch markers. Uncertain network outcomes are never automatically resubmitted after Stripe's idempotency retention window. Mission Control's Promotions page shows pending/uncertain bonus transfers and unresolved full-fare driver funding. Reconcile Stripe transfer metadata (rideId/promotionRewardId) before any manual resubmission. No new campaign is automatically activated, and Stripe mode is unchanged.

Backend-owned records: `promotionCodes`, `promotionEnrollments`, `promotionProgress`, `promotionUsage`, `promotionEvents`, `promotionRewards`, `promotionRedemptions`, and each ride's `financial/promotion` and `financial/promotionSubsidy`. Client writes are prohibited by Firestore rules.

## Checks

- `npm --prefix RydrMissionControl run test:promotions`
- `npm --prefix RydrMissionControl run build`
- `npm --prefix rydr-backend/services/stripe test`
- `npm --prefix rydr-backend test`
- Firebase functions TypeScript build and `node --test test/*.cjs`
- Firestore emulator rule tests, including reward/code isolation and blocked counter writes
- Rider and driver simulator UI checks for code entry, return navigation, and Wallet back navigation

Deploy the Stripe service before `functions:onPaidRidePromotionSettlement` and Firestore rules. The worker requires the existing `RYDR_INTERNAL_SERVICE_TOKEN` and `RYDR_STRIPE_BACKEND_URL`; no new secrets are needed. Legacy promotion records retain their previous backend handling until explicitly edited or reused into the new schema.
