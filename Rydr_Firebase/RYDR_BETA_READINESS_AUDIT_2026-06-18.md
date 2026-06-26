# Rydr TestFlight Beta Readiness Audit — June 18, 2026

Scope: RydrPlayground (rider), RydrDriver, rydr-backend, stripe-backend, rydr-bank-service, Firebase config. Goal: what's needed for a live TestFlight beta in 2 weeks.

## Verdict

Two weeks is tight but doable for a **limited, invite-only beta** with cash-only rides as the primary flow and card-pay/driver-payouts marked alpha. A beta with fully working Stripe payments and driver payouts in that window is unlikely — those flows have real backend work left, not just polish.

## Must-fix before any TestFlight build (blockers)

1. **Duplicate bundle identifier.** Both RydrPlayground and RydrDriver use `Rydr-Tech-LLC.Rydr-Drivers`. App Store Connect requires distinct bundle IDs per app — this alone blocks uploading both apps. Needs a new identifier for the rider app, a matching App ID in the Apple Developer portal, and a new provisioning profile.

2. **Mismatched development teams.** RydrDriver's main target signs with team `JMYJTGCAYG`, its test targets with `DTD5H7A5FS`. Test targets aren't archived for TestFlight so this isn't fatal, but it indicates the project settings haven't been cleaned up since being duplicated/forked — worth auditing all targets before archiving.

3. **Missing privacy strings on RydrDriver.** RydrDriver only declares `NSLocationWhenInUseUsageDescription`. Driver signup captures photos/ID (background check, identity verification flows use `SafariView`, so maybe no native camera call — confirm), but if any native `UIImagePickerController`/`PHPickerViewController`/`AVCaptureSession` call exists anywhere in RydrDriver without the matching Info.plist string, the app crashes instantly on that action in TestFlight. Worth a targeted grep for `UIImagePickerController`, `PHPickerViewController`, `AVCaptureDevice` in RydrDriver and adding `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` proactively.

4. **No Storage security rules file.** `firebase.json` only configures Firestore rules — no `storage.rules` exists in the repo. If Firebase Storage is used (profile photos, driver docs) and no rules are deployed, Storage defaults to deny-all (breaks features) or, if rules were ever set manually in console, you have no source-of-truth/version control over them. Either way this needs a real `storage.rules` file, scoped per-user, before beta.

## Security gaps in firestore.rules (real risk for any external tester)

- `cashRydrRequests`: `allow update: if signedIn()` — any authenticated user can edit any other user's Cash Hub request (price, status, anything), not just participants. Should be scoped to rider/connected-driver like `rideRequests` is.
- `responses` subcollection under `cashRydrRequests`: `allow read, create, update: if signedIn()` — same issue, any signed-in user can read/edit any driver's response to any request.
- `driver_status/{uid}`: `allow read: if signedIn()` — any signed-in user (rider or driver) can read any driver's live status document. Probably intentional (riders need to see nearby driver availability) but confirm it doesn't leak more than intended fields.
- `rideChats`: `allow read, update: if signedIn()` on the parent doc, and `allow read, create: if signedIn()` on `messages` — any signed-in user can read or write into any ride's chat thread, not just the two participants. This is a real privacy issue for a beta with real testers messaging each other.

These are tightenable in under a day each — fix before inviting any tester outside your own test accounts, since Firestore rules are the actual security boundary once the app is in someone else's hands.

## Functionally incomplete (gated safely, but not real)

These are already wrapped so they degrade gracefully in Release builds (good engineering), but they mean the feature doesn't actually work for testers:

- **Apple Sign-In / Google Sign-In** — buttons present in `LoginView.swift`, both handlers are empty `// TODO` stubs with no fallback message at all (they currently do nothing when tapped). Either wire them up or hide the buttons for beta; a dead button is worse than no button.
- **Stripe Identity verification** (driver signup step 7) — Release build shows "waiting on backend configuration," no real verification session created.
- **Checkr background check** (driver signup step 8) — Release build shows "manually bypassed only for approved beta testers," no real Checkr invitation created.
- **Stripe Connect Express payouts** (driver signup step 9) — Release build shows "needs the Stripe backend account-link route configured," no real onboarding link.
- **Push notifications** — no APNs/PushKit/`UNUserNotificationCenter` registration found anywhere in either app. Ride-request alerts, message alerts, etc. all rely on the app being foregrounded. Confirmed via code comments (`// TODO: trigger rider push notification when notification service is available.`) that this is a known, deferred gap, not an oversight you haven't seen yet.

Given this, **driver onboarding cannot reach a fully real "verified, payable driver" state today.** For a 2-week beta the realistic options are: (a) manually mark beta drivers as verified/approved in Firestore yourself and skip the three flows above, or (b) restrict the beta to cash-only rides where no payout/Connect account is needed at all, which sidesteps two of the three gaps.

## Payments (card-pay rides)

`PaymentScreenView.swift` integrates `StripePayments`/`StripePaymentsUI` and talks to a deployed backend (`rydr-stripe-backend.onrender.com`) for customer ID creation — this path looks more built-out than driver onboarding. Recommend a manual end-to-end test (real test-mode card, full ride flow) before beta to confirm the PaymentSheet/PaymentIntent round trip actually completes today; I haven't traced the full success/failure handling in this pass.

## Mock/debug code hygiene

Checked the three places mock data could leak into a Release/TestFlight build: `DebugFallbackRideService.swift`, `DriverDashboardVM.swift`'s mock ride creation, and `DriverRideInProgressView.swift`'s "Alpha Testing" disclosure group. All three are correctly wrapped in `#if DEBUG`/`#else` with real fallbacks in the `#else` branch — **none of this leaks into a Release archive.** Good. One loose end not fully verified: whether `DriverRideInProgressView`'s underlying `isMockDrivingRoute` state and `mockDriveRoute()` function declarations are themselves inside `#if DEBUG` or just unconditionally declared (harmless dead code either way, but worth a final check before archiving).

## Repo / secrets hygiene

- No `.gitignore` anywhere in the repo.
- `stripe-backend/.env` is tracked in git and contains a Stripe **test-mode** secret key (`sk_test_...`, confirmed not live). Not an active leak since it's test-mode, but it should be removed from git history and `.gitignore`'d before this repo is ever made more widely accessible, and especially before a live key is ever used.
- `node_modules/` is tracked (2132 of 2397 tracked files). Not a security issue, just repo bloat — add a `.gitignore`.
- Backend code itself (`stripe-backend/index.js`, `rydr-backend/src/config/*.js`) correctly reads all secrets from `process.env`, no hardcoded secrets in code.

## Testing

No automated test files exist in either app (0 found under any `Tests/` directory). For a 2-week timeline I wouldn't recommend trying to backfill a real test suite — instead prioritize a manual test pass on the critical paths: sign-up (rider + driver), ride request → match → complete (both cash and card), Cash Hub history/receipt behavior (the three items just fixed), chat, and the new map-snapshot ride history thumbnails.

## Recently fixed (this session, already verified)

- Cash Hub ride history now correctly appears only after a driver marks a ride completed (root cause: `status` field wasn't being flipped, only `driverQueueStatus`).
- Cash Hub history shows only the agreed price, no offer-amount fallback.
- Cash Hub history cards are no longer tappable into a connection-management sheet (no receipt exists since no money moves through the app for Cash Hub rides).
- Both RideHistoryView (rider) and Cash Rydr Hub route thumbnails now render real MapKit static map snapshots instead of decorative fake route art.

## Suggested priority order for the next 2 weeks

1. Fix duplicate bundle ID + confirm signing/provisioning for both apps (blocks any TestFlight upload at all).
2. Tighten the four firestore.rules gaps above (cashRydrRequests, responses, rideChats) — half a day, closes real privacy holes before external testers touch it.
3. Add `storage.rules` and deploy it.
4. Decide and implement the driver-onboarding strategy for beta: manual approval bypass vs. cash-only-rides-only beta.
5. Hide or wire up Apple/Google Sign-In buttons (don't ship dead buttons).
6. Manual end-to-end test of the card-payment flow with a Stripe test card.
7. Grep RydrDriver for any native camera/photo picker calls missing Info.plist strings; add them.
8. Remove `stripe-backend/.env` from git, add `.gitignore`.
9. Full manual regression pass on critical flows (no automated tests to lean on).
10. Archive builds, set up TestFlight groups, write beta tester instructions covering known gaps (no push notifications, driver verification manually handled, etc.).
