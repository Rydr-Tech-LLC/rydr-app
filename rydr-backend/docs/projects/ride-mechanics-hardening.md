# Ride mechanics hardening

Implemented and deployed to backend services November 2, 2026. No real card was charged during verification. Both iOS apps still require a new distributed build for their UI changes.

## Driver controls

The active-ride tray has **Stop requests after this ride** and **Resume** controls. The preference is stored by the backend on the driver, presence, and public profile. Matching, rematching, and acceptance reject new offers while stopped, including offers already delivered to the phone. Presence heartbeats cannot clear the preference. Starting another shift explicitly resumes requests.

Accepted queued rides remain commitments. The tray shows their count and offers a confirmed cancellation action. The driver goes offline after finishing the last accepted ride. A server sweep can promote an accepted queue even if the phone disappears after completion. Scheduled reservations retain their existing online-readiness and replacement rules.

## Authorization and settlement

Standard requests and scheduled activation first persist an `authorizing` request without a demand signal or driver offer. The Stripe service authorizes the authoritative estimate with a manually captured card PaymentIntent. Only successful authorization allows publication to dispatch. Scheduled rides place the hold at activation/dispatch, rather than holding funds indefinitely from reservation day.

The selected saved card must belong to the rider. Scheduled activation uses the current default card, falling back to a saved card when no default exists. Outstanding failed ride payments block authorization. A challenge remains attached to the same PaymentIntent; the rider can authenticate and resume the staged request. Foreground recovery surfaces unfinished authorizations, including scheduled ones.

At finalization, capture the actual amount from the existing hold when possible. If the fare increased or the hold expired, obtain a replacement authorization before cancelling the original hold. A declined increase preserves the existing hold and leaves payment unresolved for rider action. Cancellation with no fee and exhausted matching release holds. Inactive authorizations expire after 15 minutes through maintenance, with durable release jobs.

Held fares are platform charges with a separate idempotent transfer of driver earnings to the final assigned driver. This permits rematching without sending funds to the initially selected driver. Transfer failures remain recorded for reconciliation. Stripe Connect funding, account eligibility, and actual card-network authorization expiry still apply.

A frozen settlement plan prevents promotions changing across retries. Recovery retrieves the existing PaymentIntent instead of creating another payment while it is processing or awaiting authentication. Webhooks reconcile financial-outcome and ride payment state. Transient failures retry; card failures require rider action. Pre-existing rides without the new authorization policy retain their legacy settlement path.

## Other audited mechanics addressed

- Acceptance and queue promotion serialize on the driver record. The backend chooses active versus queued; one queued ride is allowed.
- Rider creation uses a transactional active-booking pointer and an active-request query, including legacy requests without pointers.
- Arrival, ride start, and completion require a recent driver location within 250 meters of the relevant stop. The driver sends fresh telemetry before these actions. Poor GPS produces a visible retry error; support can cancel a stuck trip.
- Pickup waiting derives from server arrival plus three complimentary minutes. Screen suspension and repeated intents do not reset billing.
- A no-show requires five minutes at pickup, recent nearby location, and an in-app driver message. It uses the existing rider cancellation compensation rather than an unpaid ordinary driver cancellation.
- Added stops flow through matching, route pricing, booking, and driver navigation. Stop waiting is itemized in the calculation inputs and excluded from overtime to avoid double counting.
- Accepted quotes retain their stored rates, including scheduled locked rates. Rematching only considers drivers whose current configured rates match the quote.
- Driver/admin-ended partial trips charge traveled service without the full minimum-fare adjustment. Safety disputes still use the existing support/refund workflow.
- Presence, queue, and assignment checks query active statuses instead of arbitrary slices of historical rides.

## Deployment and verification

Deploy the Firestore indexes first, then the Stripe service, core backend, Cloud Functions (including authorization release, standard-ride maintenance, payment reconciliation, and authorization notifications), and both apps. Both services and the functions must share `RYDR_INTERNAL_SERVICE_TOKEN`. Configure `RYDR_STRIPE_BACKEND_URL` on the core backend and functions, and `RYDR_BACKEND_URL` on the functions. Use the intended Stripe test/live mode consistently.

Before production rollout, exercise Stripe test-mode authorization, 3DS, decline, cancellation, no-driver release, scheduled activation with the rider app closed, lower and increased final fares, response loss after capture, and Connect transfer recovery. Provider tests used Stripe test fixtures. Full app end-to-end ride verification remains outstanding; simulator execution is unavailable on this host.

## Additional recovery fixes

The implementation is integrated onto current `main`, preserving separate Test and Live Beta Firebase projects, workspace-scoped service URLs, driver compliance, and promotion settlement. A delayed authorization response cannot release the hold after a driver has accepted.

A transactional settlement claim prevents background jobs from recharging a support-resolved or refunded balance. Manual payment resolution schedules release of any remaining holds. Terminal payment jobs cannot be regressed by a stale event retry.

Stripe refund and dispute events retrieve current provider state, preserve the original fare record, update refunded/disputed amounts, and create idempotent financial review cases. Mission Control’s Disputes page exposes these cases for driver-transfer and reward review. No automatic refund, dispute submission, or driver clawback is performed. Subscribe the existing platform webhook to `charge.refunded` and `charge.dispute.created`, `charge.dispute.updated`, and `charge.dispute.closed`.

The rider receipt now observes authoritative payment state after ride completion, including failure/retry, refunds, support resolution, and promotion-adjusted totals. This also enables tipping only after successful settlement. Added stops are retained when searching again for a replacement driver.

## Verification results

- Current-main core backend: 185 tests pass.
- Current-main Stripe suite: 151 tests pass, including authorization, capture/release, manual-resolution races, and refund/dispute reconciliation.
- Bank service: 3 tests pass.
- Cloud Functions TypeScript and Mission Control TypeScript checks succeed.
- Both apps build for generic iOS devices with signing disabled. Simulator execution remains unavailable because the host’s CoreSimulator version does not match Xcode.
- The two previously reported payout failures were test-clock errors: tests used the real date while their service used a fixed clock. They now use the injected clock, and the full Stripe suite passes.
- Actual Stripe test-mode provider checks passed through the existing Render service: reserve $25 without capturing, capture a $23 final fare, retry that capture without duplicating it, release an unused hold, decline an unusable card, and require off-session 3DS. These isolated provider checks used test card fixtures without creating a Firebase ride or moving real money; they do not replace app end-to-end testing.

The existing Render Stripe service has Test and Live keys and its internal service token configured. The deployed workspace bootstrap reports authentication version 2 and the expected separate Firebase projects. The Render workspace displays a billing-payment warning.

## Backend rollout — November 2, 2026

- Commit `33716f0` was pushed directly to main. Render confirms that both the Stripe and core backend services are live on this commit; both health checks return HTTP 200.
- Firebase authentication was refreshed. Firestore indexes were deployed to the Test default database and the Live project default and live-beta databases. All 17 composite indexes report READY in both the Test default and Live Beta databases.
- Eight targeted functions deployed successfully in each workspace: payment job handling, paid-ride promotion settlement, authorization release jobs, payment maintenance, standard ride maintenance, request-created notifications, rematch notifications, and authorization-required notifications. All 16 report ACTIVE. Live triggers target only the live-beta database; Test triggers target the Test default database.
- Functions use the existing service token and the verified service URLs: core `https://rydr-backend-2cl9.onrender.com` and Stripe `https://rydr-stripe-backend.onrender.com`. Local ignored dotenv files preserve these nonsecret deployment parameters.
- Existing Test and Live platform Stripe webhook endpoints now include refund and dispute-created/updated/closed events. Existing event subscriptions, destination URLs, and signing secrets are preserved.
- Validation also includes 62 Cloud Functions tests and 18 Firestore rules tests, for 419 passing automated tests in total.
- No live charge, refund, payout, or driver clawback was initiated by this rollout. The mobile UI changes are in source and build successfully; they are not yet distributed through TestFlight or the App Store.
