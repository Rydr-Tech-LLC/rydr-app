# Mission Control workspaces

Mission Control has two operational workspaces. The selector stays visible in the sidebar, and the URL includes the workspace so separate browser tabs cannot silently change each other's data context.

| Workspace | Firebase project / database | Stripe | Accounts |
| --- | --- | --- | --- |
| Test | `rydr-test-c7ec1` / `(default)` | Test keys only | Independent Test identities; preserved beta Test accounts |
| Live Beta | `rydrapp-c7ec1` / `live-beta` | Live keys only, gated by both live switches | Independent real identities participating in the live beta |

Accounts, ride requests, trips, support disputes, safety flags, rider/driver campaigns, rewards, payment jobs, and driver payouts live in the selected database. Staff authentication and access management remain shared. Live Beta starts with operating configuration and independent vehicle-library assets, without copying Test accounts, rides, promotions, disputes, or balances. The account-reset security archive remains in the control database and outside both operational lists.

Authentication v2 uses independent Firebase projects. Email, phone, password and social-provider ownership are scoped to each project, so the same email and phone can be registered in both. Firebase mock phone numbers belong only in the Test project's Auth configuration. The original project's legacy Test UIDs remain blocked for Live Beta, even after their credentials are retired. Staff accounts and the security archive stay in the original control database.

External backend credentials use a restricted Workload Identity Federation provider to impersonate `rydr-test-backend@rydr-test-c7ec1.iam.gserviceaccount.com` with short-lived tokens. The provider accepts only the existing backend service account's signed Google identity. No new service-account private key or organization-policy exception is required. Test Functions run under the dedicated Test identity. FCM transport uses the original iOS registration, with workspace-scoped device tokens and payloads.

Deploy Test with `firebase deploy --project rydr-test-c7ec1 --config firebase.test.json --only functions,firestore,storage --non-interactive --force` from `rydr-backend/firebase`. Test callable/HTTP handlers retain Firebase/application authentication; their Cloud Run services use `run.googleapis.com/invoker-iam-disabled=true` instead of an organization-prohibited `allUsers` IAM binding. Keep event-driven and scheduler services protected by IAM. Recheck these six HTTP services after deploying: `decodeVin`, `getVehicleImage`, `submitVehicleVin`, `submitVehicleManual`, `deleteDriverVehicle`, `editVehicleLibraryBackground`.

## Mobile routing

The rider and driver apps explicitly choose Test or Live Beta before sign-in, then verify the server project map. Workspace switching requires signing out. The selected project owns Auth, Firestore, Storage and Functions. Every backend verifies the token against the selected, allowlisted project, checks revocation and the canonical account, and rejects tokens from the other project even when the UID, email or phone matches. Headers cannot select an account’s Stripe mode. Rules enforce the project/database boundary; missing configuration fails closed.

The rider obtains its Stripe publishable key from authenticated `/account-config`, bound to the current workspace and UID. Driver payout components validate key mode and obtain authenticated account sessions from the selected workspace. Bundled Stripe keys are not a fallback for account configuration.

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
