# Rydr Phase 1 Controlled Beta Audit

Date: 2026-06-28  
Target: August 1, 2026  
Scope: Rydr rider app, Rydr Driver app, Firebase rules/storage/functions, Stripe backend, Rydr backend, Mission Control as supporting admin surface.  
Beta size: maximum 50 riders and 10 drivers.

## Executive Verdict

Rydr is not ready for a public beta or production money flow. It can be made ready for a Phase 1 controlled beta by August 1 only if the beta is explicitly constrained:

- Drivers must be hand-vetted and manually approved.
- Standard rides must be treated as operational test rides, not production-grade transportation automation.
- Real-money card charging should either be disabled for beta or limited to tightly supervised Stripe test/live pilot cases after backend auth/idempotency is fixed.
- Push notifications cannot be assumed reliable until sender jobs are implemented and production APNs entitlements are confirmed.
- Cash Rydr Hub can be used as the safer early beta path if privacy rules are tightened further and participants are briefed that payment is off-platform.

The largest remaining product risk is the rider app standard-ride lifecycle. After a driver accepts a request, the rider app currently starts its own timer-driven simulation and can complete/charge based on that simulation, rather than driving the rider state from the driver app's real ride status.

## What Has Improved Since The Earlier Audit

- Rider and driver bundle identifiers are now distinct.
  - Rider: `com.khris.rydr.RydrPlayground`
  - Driver: `Rydr-Tech-LLC.Rydr-Drivers`
- RydrDriver signing teams appear aligned to `DTD5H7A5FS`.
- Firebase Storage rules now exist and are wired in `Rydr_Firebase/firebase.json`.
- Notification token registration exists in both apps.
- Ride chat Firestore rules are now participant-scoped.
- Cash Hub update rules are tighter than before.
- Stripe Identity and Connect backend endpoints now exist in `stripe-backend/index.js`.
- Driver profile photo moderation/storage has a real path.
- Work Zone and Destination Filter were just tightened in the driver/rider matching path.

These are meaningful improvements, but several beta blockers remain.

## P0 - Must Fix Before Inviting External Testers

### 1. Standard ride lifecycle is still simulated on the rider side

Files:
- `Features/Booking/RideManager.swift`

Evidence:
- `handleAccept()` creates an in-memory `Ride` and calls `startDriverMovement()`.
- `startDriverMovement()` moves the driver marker on a timer.
- `completeRide()` creates a receipt and calls `chargeRiderForRide()` based on local state.
- Fare estimates still come from string hashing in `estimateFor(pickup:dropoff:)`.

Risk:
- Rider UI can show pickup, waiting, dropoff, completion, receipt, and charge without those states being confirmed by the driver app.
- This is not acceptable for unsupervised paid rides.

Required beta decision:
- For August 1, either disable automatic real card charging for standard rides or rewire rider state to listen to Firestore `rides/{id}` / `rideRequests/{id}` status written by the driver app.

Minimum August 1 acceptable fix:
- Rider creates request.
- Driver accepts.
- Rider screen listens to backend ride status.
- Driver app controls arrived/start/complete.
- Rider only charges after backend/driver completion status is observed.
- Payment failure must be visible and persisted.

### 2. Stripe backend payment/customer routes are not consistently authenticated or ownership-checked

File:
- `stripe-backend/index.js`

Evidence:
- `verifiedFirebaseUid()` exists, but several sensitive routes accept only client-provided identifiers:
  - `/create-customer` accepts unauthenticated fallback `uid`.
  - `/ephemeral-key` only needs `customerId`.
  - `/create-setup-intent` only needs `customerId`.
  - `/create-payment-intent` only needs `customerId`, `paymentMethodId`, and optional `driverAccountId`.
  - `/list-payment-methods`, `/set-default-payment-method`, `/detach-payment-method` only need Stripe IDs.
  - `/connect/account-link`, `/connect/status`, `/connect/balance`, `/connect/instant-payout` are not ownership-checked.

Risk:
- Anyone with backend URL and Stripe object IDs can potentially inspect, mutate, charge, or payout against accounts.

Required fix:
- Require Firebase ID token on every non-webhook route except health/return pages.
- Server-side verify the authenticated user owns the `customerId`, `paymentMethodId`, `accountId`, and driver profile.
- Add idempotency keys for customer, setup intent, payment intent, account creation, and payout creation.

### 3. Real-money beta must not proceed until Stripe idempotency and charge error handling are fixed

Files:
- `stripe-backend/index.js`
- `Features/Booking/RideManager.swift`

Evidence:
- `create-payment-intent` does not use an idempotency key.
- `chargeRiderForRide()` logs failures but does not mark the ride/receipt/payment as failed in Firestore or show a rider-facing recovery path.
- Saved-card fallback leaves mock cards in place when no real Stripe payment methods load.

Risk:
- Retry can double-charge.
- Failed charge can look like a completed ride.
- A tester can complete a ride with no real payment method and no clear blocking UI.

Required fix:
- Persist `payments/{paymentId}` or `rides/{id}.paymentStatus`.
- Block paid ride start if no real saved card is present.
- Surface failed payment and retry.
- Add idempotency keys based on ride ID + charge attempt.

### 4. Driver onboarding is not production-grade; use manual vetting only

Files:
- `RydrDriver/RydrDriver/Features/SignUp/IdentityVerificationView.swift`
- `RydrDriver/RydrDriver/Features/SignUp/BackgroundCheckView.swift`
- `RydrDriver/RydrDriver/Features/SignUp/PayoutsSetupView.swift`

Current state:
- Stripe Identity is now wired to a backend session endpoint.
- Stripe Connect onboarding is wired to backend endpoints.
- Background checks remain beta-deferred; there is no real Checkr integration.
- Driver approval still depends on manually written Firestore fields.

Required beta operating rule:
- All 10 beta drivers must be personally vetted outside the app.
- Maintain a driver approval spreadsheet/checklist.
- Only manually set `betaTester`, `betaBackgroundCheckBypassEnabled`, and approval fields after vetting.
- Do not claim automated background checks are complete.

### 5. Firestore privacy is better, but Cash Hub reads are still broad

File:
- `Rydr_Firebase/firestore.rules`

Evidence:
- `cashRydrRequests/{requestId}` read is `if signedIn()`.
- `cashRydrRequests/{requestId}/responses/{responseId}` read is `if signedIn()`.
- `driver_status/{uid}` read is `if signedIn()`, exposing live-ish driver status/location fields to every signed-in user.

Risk:
- Any signed-in beta user can read all Cash Hub requests/responses.
- Any signed-in user can read all driver status docs.

Required fix before external testers:
- For Cash Hub, read should be owner, responder, connected driver, or admin. If browsing open requests is required, split public browse-safe fields from private request details.
- For driver status, expose only rounded/limited location through `publicDriverProfiles` for marketplace discovery; keep exact status/location participant/admin scoped.

### 6. Driver app is missing photo-library privacy strings while using PhotosPicker

Files:
- `RydrDriver/RydrDriver/Info.plist`
- `RydrDriver/RydrDriver/Features/SignUp/DriverLicenseView.swift`
- `RydrDriver/RydrDriver/Features/SignUp/VehicleInfoView.swift`
- `RydrDriver/RydrDriver/Features/Dashboard/DriverSideMenuView.swift`

Evidence:
- Driver app uses `PhotosPicker`.
- Driver `Info.plist` currently only contains URL schemes, `NSApplicationCrashOnExceptions`, and background modes.
- Location usage is injected from project settings, but photo usage strings are not present in the plist/project settings found.

Required fix:
- Add `NSPhotoLibraryUsageDescription`.
- Add `NSCameraUsageDescription` if any camera capture will be introduced or if UI says camera.
- Manually test every upload/photo button on a TestFlight build.

### 7. Push notification receiving exists, sending is not complete enough to rely on

Files:
- `Core/NotificationManager.swift`
- `RydrDriver/RydrDriver/Core/DriverNotificationManager.swift`
- `rydr-backend/src/routes/notifications.js`
- `rydr-backend/src/services/notificationService.js`

Current state:
- Apps request permission, register APNs/FCM tokens, and store token docs.
- Backend notification route returns mock notifications.
- Driver lifecycle still has TODO comments for rider push events.
- Entitlements are set to `development`; production/TestFlight push must be verified in Apple capabilities.

Required beta operating rule:
- Testers must keep the app open during ride tests unless push senders are implemented and verified.

### 8. Backend service auth and dependency hardening are incomplete

Files:
- `rydr-backend/src/app.js`
- `rydr-backend/src/routes/*.js`
- `rydr-backend/src/routes/moderation.js`
- package lockfiles

Findings:
- Only moderation route verifies Firebase token.
- `/driver/wait-time-events` and `/driver/account-deletion-requests` accept client body IDs without auth.
- Chat/community routes are placeholders.
- `npm audit --omit=dev --audit-level=high` reports high severity advisories in both `stripe-backend` and `rydr-backend`.

Required fix:
- Add Firebase auth middleware to every state-changing backend route.
- Verify body IDs match the token UID.
- Patch dependencies with `npm audit fix` where safe; schedule breaking updates where required.

### 9. Rider login still shows dead social sign-in buttons

File:
- `Features/SignUp/LoginView.swift`

Evidence:
- Apple/Google login buttons contain TODO handlers.
- Sign-up flow has Google/Apple wiring in `NameEntryView`, but login screen buttons do nothing.

Required fix:
- Hide those buttons for Phase 1 or wire them correctly.

### 10. Account deletion is incomplete for rider app and only a request queue for driver app

Files:
- `RydrDriver/RydrDriver/Features/Dashboard/DriverDashboardVM.swift`
- `RydrDriver/RydrDriver/Core/RydrBackendService.swift`
- `rydr-backend/src/services/driverService.js`
- rider app files: no equivalent deletion path found.

Risk:
- App Review can block apps with account creation but no in-app deletion path.
- Driver deletion request does not perform actual deletion/anonymization.

Required fix:
- Add rider account deletion request UI.
- Make both apps write `accountDeletionRequests`.
- Document manual admin process for Phase 1.

## P1 - Important Before August 1, But Can Be Operationally Managed

### A. TestFlight/APNs setup

- Entitlements show `aps-environment = development`.
- Confirm Apple Developer capabilities and TestFlight builds use production APNs entitlement after archive.
- Do real-device TestFlight token registration test.

### B. Driver/rider support is usable but incomplete

- Rider support tickets, chat, disputes, and callback requests now persist to Firestore.
- Attachment uploads are not available.
- Mission Control needs a practical workflow to read/respond to tickets.

### C. Mission Control is not a complete beta operations console

Useful for admin tasks, drivers/riders, reports, vehicle library. Still needs:
- Driver approval workflow for beta.
- Support ticket inbox.
- Ride monitoring/debug view.
- Payment failure queue.
- Safety report intake workflow.

### D. Route estimates are not real

- Standard ride estimate uses deterministic placeholder logic.
- Driver route previews use MapKit in places, but fare estimate source is not authoritative.
- For Phase 1, fares must be labeled beta estimates, or real routing must be added before charging.

### E. Repo/deploy hygiene

- There are multiple Node services and an old nested driver stripe backend. Reduce deploy confusion.
- Add deployment runbooks: Firebase rules/functions, Rydr backend, Stripe backend, Mission Control.
- Keep `.env` and service account material out of git.

## Phase 1 Recommended Scope

### Recommended beta mode

Use a supervised hybrid:

1. Primary: Cash Rydr Hub / manually coordinated rides.
2. Secondary: Standard ride matching with no automatic live charge until lifecycle is fixed.
3. Optional: one or two internal Stripe test-card rides only after backend auth/idempotency work.

### Drivers

- Max 10.
- All manually vetted before being enabled.
- Require each driver to complete:
  - Firebase/Auth account.
  - Profile photo.
  - Vehicle info/VIN flow.
  - License/insurance upload where available.
  - Manual background and license check outside app.
  - Manual Firestore approval.
  - Dry run with staff.

### Riders

- Max 50.
- Invite-only.
- Must sign beta acknowledgement:
  - App is in controlled beta.
  - Keep app open during tests unless told push is ready.
  - Cash Hub payments are off-platform.
  - Report safety/payment issues immediately.
  - Rydr may manually review ride records and support tickets.

## August 1 Work Plan

### Week 1: Security and deploy blockers

1. Add auth/ownership checks to Stripe backend.
2. Add idempotency to Stripe writes.
3. Patch high-severity npm audit items where non-breaking.
4. Tighten Cash Hub and driver status Firestore reads.
5. Add driver photo/camera privacy strings.
6. Hide or wire rider login Apple/Google buttons.
7. Add rider account deletion request.
8. Confirm TestFlight bundle IDs, teams, capabilities.

### Week 2: Standard ride lifecycle decision

Pick one:

- Safer path: disable real card auto-charge for standard rides and run only supervised/cash beta.
- Better path: rewire rider active ride screen to Firestore ride status and only charge on driver completion.

Also:
- Add payment failure persistence.
- Add manual payment test checklist.
- Add operations docs for manual driver approval.

### Week 3: End-to-end beta rehearsal

Run full rehearsals:
- New rider signup/login.
- New driver signup/login.
- Manual driver approval.
- Driver online/offline.
- Work Zone/Destination Filter.
- Rider driver discovery.
- Standard request accept/decline.
- Active ride lifecycle.
- Cancellation paths.
- Support ticket/dispute/callback.
- Cash Hub request/response/complete.
- Push token registration.
- Profile photo moderation.
- Vehicle library image display.

### Week 4: TestFlight and operations readiness

1. Archive both apps.
2. Upload to TestFlight.
3. Create separate groups: internal staff, 10 drivers, 50 riders.
4. Seed beta drivers and approved ride types.
5. Prepare Mission Control/admin coverage.
6. Publish beta instructions and known limitations.
7. Run final real-device smoke test.

## Go / No-Go Checklist

Do not start external beta unless all are true:

- Both apps archive and install through TestFlight.
- Firebase Firestore and Storage rules deploy cleanly.
- Stripe backend requires Firebase auth and validates ownership on all sensitive routes.
- No route can charge a rider or payout a driver based only on client-provided Stripe IDs.
- Driver photo picker does not crash on TestFlight.
- Rider login has no dead Apple/Google buttons.
- Rider account deletion request exists.
- Driver account deletion request exists and support knows the manual process.
- Cash Hub private details are not readable by every signed-in user.
- Standard rides either use real driver lifecycle state or card charging is disabled for beta.
- Every beta driver is manually vetted and approved.
- Support/safety escalation owner is assigned during every scheduled test window.

## Bottom Line

August 1 is achievable for a controlled, hand-held beta if Rydr treats this as an operations pilot, not a production launch. The safest beta is: 10 personally vetted drivers, 50 invite-only riders, Cash Hub or no-auto-charge standard rides, heavy staff supervision, and explicit tester instructions.

August 1 is not achievable for unsupervised paid rides with production-grade driver vetting, lifecycle tracking, payouts, and automated safety operations unless the standard ride lifecycle and backend security work are completed immediately.
