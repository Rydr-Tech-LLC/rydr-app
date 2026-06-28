# Rydr Beta Hardening Sprint — Phase 4 Deliverable

**Scope:** Operations features — push notification senders, account deletion workflow, support/payment failure queues, driver approval workflow improvements.
**Date:** June 28, 2026

## Executive Summary

Phase 4 closes the operational gaps that would otherwise leave the beta team without tooling to run the platform day-to-day: there was no way to push notifications on key events, no way for a rider or driver to actually get their account deleted once they requested it, no queue for support conversations or failed payments, and the driver-facing app had no visibility into payment outcomes. All four areas are now implemented end-to-end — Cloud Functions triggers, Mission Control admin UI, rider/driver app UI, and the cross-service Stripe cleanup call needed to close out a deletion safely.

Nothing in this phase touches the existing decision to keep rider-side automatic charge-on-completion disabled (see Remaining Beta Risks below) — that scope boundary was deliberately respected rather than silently expanded.

## Files Modified

**Cloud Functions (`Rydr_Firebase`)** — completed in a prior session, unchanged this phase: `notificationSender.ts`, `onRideUpdated`, `onSupportMessageCreated`, `onDriverApprovalDecision` triggers.

**stripe-backend**
- `index.js` — added `requireAdminUid()` and `POST /admin/cleanup-account`.

**RydrMissionControl**
- `lib/types.ts` — added `AccountDeletionRequestRecord`, `RideRecord`, `SupportTicketRecord`, `SupportMessageRecord`, extended `AuditLogEntry.targetType`.
- `components/StatusPill.tsx` — added styles for `requested`, `processing`, `succeeded`, `failed`, `refunded`.
- `components/Sidebar.tsx` — added nav entries for Payment Failures, Support Inbox, Account Deletions.
- New: `app/(portal)/account-deletions/page.tsx`, `AccountDeletionActions.tsx`, `app/api/account-deletions/[id]/process/route.ts`.
- New: `app/(portal)/payment-failures/page.tsx`, `PaymentFailureActions.tsx`, `app/api/payment-failures/[id]/action/route.ts`.
- New: `app/(portal)/support/page.tsx`, `support/[id]/page.tsx`, `support/[id]/SupportReplyForm.tsx`, `app/api/support/[id]/reply/route.ts`.

**RydrPlayground (rider app)**
- `Features/Booking/RideManager.swift` — added `backendRideId` to `Receipt`, threaded through all construction sites.
- `Features/Booking/EndRideView.swift` — added `paymentStatusCard` (failed/processing states, Retry + Update Card actions); changed `rideManager` to a non-optional `@ObservedObject`.
- `Features/Booking/RideInProgressView.swift` — passes `rideManager` into `EndRideView`.

**RydrDriver (driver app)**
- `Features/Driver Logic/DriverDispatchModels.swift` — added `paymentStatus` to `DriverActiveRide`.
- `Features/Driver Logic/DriverEndRideView.swift` — added `paymentStatusBanner` (failed/pending/succeeded states, read-only).

## Architectural Changes

Mission Control authenticates admins via session cookie, not a Firebase ID token, so it had no existing way to call stripe-backend's admin-gated routes. Rather than building a token-exchange flow, a shared-secret server-to-server header scheme (`x-internal-admin-secret` + `x-admin-uid`) was added to stripe-backend alongside its existing Firebase-claim check — Mission Control's own session check still gates who can trigger the call; the secret only proves the call came from a trusted backend.

Account deletion anonymizes Firestore profile data rather than hard-deleting it, preserving referential integrity for historical ride and ledger records, while fully removing the Firebase Auth account and disabling FCM tokens. The cleanup flow is idempotent — both Stripe cleanup and Auth deletion tolerate "already gone" errors, so a failed run can be safely retried from the queue.

Payment failure handling in Mission Control deliberately never calls Stripe directly. "Resolve" and "write off" only update Firestore ledger state; actual refunds still flow through stripe-backend's existing webhook-driven paths, which avoids any risk of a double-refund from two services touching Stripe independently.

## Security Improvements

- Admin replies to support tickets are written via the Admin SDK specifically because Firestore rules restrict client-writable `senderRole` to `rider`/`driver` — only this privileged server path can ever produce a `senderRole: "admin"` message, which is also the field the push-notification trigger checks before notifying the ticket owner.
- The new stripe-backend admin endpoint is gated by `requireAdminUid()`, checked before any account or customer mutation.
- All deletion, payment-failure, and support actions write to the existing audit log (`writeAuditLog`) with admin uid/email, action, target type, and reason.

## Payment Improvements

- Rider app: a failed-payment card now appears at the top of the post-ride receipt with **Retry Payment** (calls the existing `retryFailedPayment`) and **Update Card** (links to `PaymentMethodView`), plus a "Finishing up payment…" state while a charge is processing.
- Driver app: a read-only banner shows whether the rider's fare succeeded, is pending, or failed — drivers are told explicitly no action is needed on their end.
- Mission Control: a Payment Failures queue lists failed rides with retry count, failure reason/code, and manual Resolve/Write-Off actions for cases the in-app retry won't fix.

## Firestore / Backend Changes

- No Firestore security rule changes were required this phase — existing rules (e.g. `senderRole` restriction on `supportTickets/{id}/messages`) already supported the design; Phase 4 exploited them rather than altering them.
- stripe-backend: new `POST /admin/cleanup-account` route, deletes the Stripe customer (tolerating `resource_missing`) and deactivates/rejects the Connect account with a capabilities-update fallback if `accounts.reject` is declined.

## Remaining Beta Risks

1. **Rider-side automatic charge-on-completion is still intentionally disabled.** `chargeRiderForRide` is fully implemented in `RideManager.swift` but never called — `recordClientChargeDisabled` is a deliberate no-op labeled "Phase 1 beta." This phase only added Retry-after-failure and status-display UI, which will light up correctly once a future phase enables real charging or webhook-driven status updates start firing. Flipping that switch is a payment-architecture decision outside Phase 4's scope and needs an explicit go-ahead before beta launch with real payments.
2. **Mission Control TypeScript verification could not be run in this environment.** The project lives on an iCloud-synced path, and a clean dependency install hit both filesystem lock errors (`Resource deadlock avoided`) and npm registry restrictions (403s on some packages) in the sandbox. Cloud Functions (`tsc --noEmit`) and stripe-backend (`node -c`) both verified cleanly; Mission Control changes were instead verified by full manual read-through of every new/edited file. Recommend running `npx tsc --noEmit` and `npx next lint` locally (outside this sandbox) before merging.
3. **Stripe cleanup depends on env vars being set** (`STRIPE_BACKEND_BASE_URL`, `RYDR_INTERNAL_ADMIN_SECRET`) in both Mission Control and stripe-backend deployments. If unset, account deletion still completes (Auth + Firestore), but Stripe cleanup is skipped and logged — needs a follow-up audit-log alert or a dashboard surface so skipped cleanups don't go unnoticed.
4. **Account deletion is irreversible** once `complete` runs (Auth user is deleted). There's no "undo" — only careful queue review via the `requested`/`processing`/`rejected` states stands between a request and execution.

## Production Readiness Score

**7/10** for a controlled beta launch with real users. Core operational tooling (notifications, deletion, support, payment failure handling, driver approval) is now in place and architecturally sound. The score is held back primarily by item 2 above (unverified TypeScript compile in this environment) and item 1 (payment charging intentionally still off) — neither is a defect, but both need explicit sign-off before a real-money beta.

## Pre-Launch Recommendations

1. Run `npx tsc --noEmit` and `npx next lint` against Mission Control on a non-iCloud-synced machine or CI runner to get a clean compile signal before merge.
2. Decide explicitly whether/when `chargeRiderForRide` gets wired into the ride-completion path — this is the single biggest remaining gap between "beta with operational tooling" and "beta that actually charges riders automatically."
3. Set `STRIPE_BACKEND_BASE_URL` and `RYDR_INTERNAL_ADMIN_SECRET` in both Mission Control and stripe-backend production environments before relying on the account-deletion Stripe cleanup path.
4. Smoke-test the full account-deletion flow once against a Stripe test-mode account and a disposable Firebase Auth user, end-to-end, before the first real deletion request comes in from a beta user.
5. Spot-check the new Mission Control pages (Account Deletions, Payment Failures, Support Inbox) against the Firestore emulator or a staging project to confirm query indexes exist for the `orderBy`/`where` combinations used (`rides` on `paymentStatus == "failed"` + `orderBy("lastPaymentAttempt")` will need a composite index).
