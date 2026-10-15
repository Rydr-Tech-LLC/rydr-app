# Live Beta reset preparation

The October 15, 2026 account inventory is private and is deliberately not committed. The review package contains the exact keep/reset decisions and the archive/recovery procedure. It is an inventory, not deletion authorization.

Preserve Firebase-configured test phone numbers and their Auth identities, all admin/staff access, and identities requiring manual review. Account deletion must be UID scoped across both rider/driver roles and revalidate protection immediately before each operation. Archive linked records and vehicle/plate history, verify recovery, resolve active rides and financial work, then request approval of the exact reset scope. No live Stripe objects may be deleted as a side effect.

## Live-operation safeguards

`operationalSecurity/liveBetaAccess` is server-only under the existing Firestore deny-by-default rules. Version 1 contains `configured: true`, `blockedAuthUids`, `blockedPhoneHashes` (SHA-256 of canonical E.164), source and synchronization timestamp. Never store Firebase test verification codes in this document or in the review package. Sync from Firebase's authoritative configured test-number set before live activation and whenever that set changes.

The backend reads `platformConfig/stripeRuntime` to distinguish test/live operation. Live ride routes, online presence and scheduled rides validate the authenticated identity; matching and rematching exclude preserved test accounts. Selected drivers are checked on booking and initial dispatch. Stripe operations validate the account using authoritative Auth data; background ride charges, instant/weekly payout claims and driver promotion transfers enforce the same policy. Missing live protection or unavailable Auth checks fail closed. Admin login is unaffected. Test mode is unchanged.

Existing test drivers may still have an online presence when the global runtime changes, so candidate filtering is required in addition to preventing new online requests. UID denial persists after phone changes. Auth phone hashing blocks new UIDs created using a configured test number. Configured test numbers must not be inferred from prefixes or user-editable profile labels.

## Separate work: simultaneous account-specific Stripe environments

A new app build has been authorized as an acceptable approach. Current rider configuration is an unauthenticated, session-cached `/config` request, and the backend activates one global Stripe mode. Simultaneous test/live Stripe is not implemented by the safeguards above.

Before implementing it, replace global mode activation/migration with account-specific mode resolution, authenticated runtime configuration, separate Stripe clients/keys and customer/Connect/Identity state. Update rider/driver configuration caches on sign-in/account change and bind each financial operation to its originating mode. Preserve independent idempotency, promotion progress, balances and payout jobs. Isolate ride matching by environment. Verify test accounts cannot reach a live Stripe client even with a forged request or direct endpoint call. Neither a public key switch nor a Mission Control label supplies that isolation.

No account deletion or switch to live mode is part of this preparation change.
