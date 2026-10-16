# Mission Control workspaces

Mission Control has two operational workspaces. The selector stays visible in the sidebar, and the URL includes the workspace so separate browser tabs cannot silently change each other's data context.

| Workspace | Firestore database | Stripe | Accounts |
| --- | --- | --- | --- |
| Test | `(default)` | Test keys only | Preserved Firebase test identities and configured Firebase test phone numbers |
| Live Beta | `live-beta` | Live keys only, disabled until explicitly enabled | Real verified identities participating in the live beta |

Accounts, ride requests, trips, support disputes, safety flags, rider/driver campaigns, rewards, payment jobs, and driver payouts live in the selected database. Staff authentication and access management remain shared. Live Beta starts with operating configuration and independent vehicle-library assets, without copying Test accounts, rides, promotions, disputes, or balances. The account-reset security archive remains in the control database and outside both operational lists.

The identity policy is an exact snapshot of Firebase’s configured test numbers, rather than a phone-prefix match. If those Firebase test numbers change, synchronize the phone list and hashes in both databases’ `operationalSecurity/liveBetaAccess` records before using the new numbers. Keep previously pinned Test UIDs in the policy.

## Mobile routing

The rider and driver apps fetch a hashed identity policy before displaying their screens. A signed-in Firebase UID or canonical phone matching the configured Test policy selects Test automatically; other identities select Live Beta. There is no account-controlled environment picker. Every Firestore reference, callable function, and Rydr backend request follows that selection. Backends independently verify the current Firebase identity and reject cross-workspace requests. Rules also enforce the database boundary. Missing policy or payment configuration fails closed.

The rider obtains its Stripe publishable key from authenticated `/account-config`, bound to the current UID. Driver payout components validate key mode and obtain authenticated account sessions from the selected workspace. Bundled Stripe keys are not a fallback for account configuration.

## Stripe environment variables

Keep `STRIPE_SECRET_KEY` and `STRIPE_PUBLISHABLE_KEY` in Test mode. Explicit `STRIPE_SECRET_KEY_TEST` and `STRIPE_PUBLISHABLE_KEY_TEST` can be provided as permanent Test overrides; these are required before changing the legacy variables to live values. Never replace the only copy of the Test keys.

Prepare Live Beta separately with:

- `STRIPE_SECRET_KEY_LIVE` and `STRIPE_PUBLISHABLE_KEY_LIVE`
- `STRIPE_WEBHOOK_SECRET_LIVE` and `STRIPE_CONNECT_WEBHOOK_SECRET_LIVE`
- `STRIPE_DRIVER_VERIFICATION_FLOW_ID_LIVE` and `STRIPE_RIDER_VERIFICATION_FLOW_ID_LIVE`

Preserve the corresponding Test webhook secrets and Identity flows. Both webhook destinations retain the existing public paths `/webhook` and `/webhook/connect`; the service verifies the signature and routes the signed event to its own Stripe mode and database.

`LIVE_BETA_ENABLED` defaults to false. No live public key is returned and no live Stripe app is served while disabled or incompletely configured. Test routes continue to use Test keys even when Live Beta is enabled.

## Activating a live beta later

1. Install and verify the workspace-aware rider and driver builds. Existing builds only support the legacy Test database.
2. Configure the complete Live Stripe key, webhook, and Identity set in Render, while retaining Test configuration. Resolve Stripe live payout eligibility before offering unavailable payout methods.
3. Explicitly enable `LIVE_BETA_ENABLED=true` on the Stripe service and redeploy. Keep the Firestore workspace flag false while checking the configuration; live endpoints remain blocked.
4. When ready to start the live beta, set `platformConfig/workspace.livePaymentsEnabled=true`. Both switches must be enabled: this releases Live Stripe endpoints, financial operations, and scheduled jobs, and removes the preparation banner. Verify authenticated real-account configuration reports Live and Test identities still report Test. The first Live `/config` request prepares `platformConfig/stripeRuntime`; rides also require this runtime to be ready.
5. Approve real beta invitations, driver documents, and the selected vehicle in the Live Beta workspace; Test approvals do not carry over.

This implementation does not enable Live Beta payments automatically. Test external email/SMS delivery is simulated; Test financial operations use Stripe's Test API. Notifications carry their workspace. The apps reject taps and foreground banners from the other environment; background push delivery continues to rely on the existing device-token registration and logout cleanup.

## Validation

Run the main backend, Stripe, bank, Mission Control, Functions, and Firestore Rules suites. The rules emulator requires Java 21; its current CLI does not support named databases, so named-database trigger binding and database selection are covered by Functions tests, alongside the default-database security-rule tests. Before release, verify production workspace navigation, Test account isolation, Stripe Test configuration, and both simulator builds. Prepare signed iOS archives without uploading them until a release is requested.
