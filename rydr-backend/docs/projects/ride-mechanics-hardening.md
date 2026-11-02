# Ride mechanics hardening

Implemented November 2, 2026. This change is local source work; it does not deploy services or initiate real charges.

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

Before production rollout, exercise Stripe test-mode authorization, 3DS, decline, cancellation, no-driver release, scheduled activation with the rider app closed, lower and increased final fares, response loss after capture, and Connect transfer recovery. No live payment, deployment, or simulator ride was performed by the source implementation task.

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

The existing Render Stripe service has Test and Live keys and its internal service token configured. The deployed workspace bootstrap reports authentication version 2 and the expected separate Firebase projects. The Render workspace displays a billing-payment warning. Firebase deployment was attempted but stopped because the local CLI login expired; indexes and functions are not yet deployed from this branch. Refresh the existing Firebase login before continuing rollout.
