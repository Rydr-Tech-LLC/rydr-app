# Rydr Beta Readiness — Punch List (target: Aug 1)

Compiled from a full code audit of RydrDriver, the rider app (RydrPlayground/App/Core/Features), and all backend services. Items are ordered by blast radius, not by file. Effort estimates assume one engineer who already knows this codebase.

Legend: **P0** = must fix before any real money/real strangers go live. **P1** = must fix before a public (non-hand-picked) beta. **P2** = should fix soon, won't sink the beta.

---

## P0 — Blockers (real money, real safety, real security)

| # | Issue | Where | Effort |
|---|---|---|---|
| 1 | Stripe backend has **no auth** on `/create-payment-intent`, `/connect/accounts`, `/connect/instant-payout`, `/connect/status`, `/connect/balance`. Anyone with the URL can move money or read balances. | `stripe-backend/index.js` | 1–2 days (add Firebase ID token verification middleware to every route) |
| 2 | Stripe backend is still on **test-mode keys** (`sk_test_...`). | `stripe-backend/.env` (Render env vars) | 30 min once Stripe live account is approved |
| 3 | No **idempotency keys** on payment-intent / instant-payout creation — retried mobile requests can double-charge or double-pay. | `stripe-backend/index.js`, `rydr-bank-service/server.js` | 1 day |
| 4 | Rider ride lifecycle is a **client-side fake simulation** decoupled from the real driver. Timer-driven movement/arrival/completion; real Firestore `driverLocationStream` exists but is never called. Ride auto-"completes" (and charges the rider) on a fixed timer regardless of the real driver's status. | `Features/Booking/RideManager.swift` — `handleAccept()` ~577, `startDriverMovement()` ~717, `completeRide()` ~769 | This is the single biggest item — likely 1–2 weeks to rewire rider UI to consume real driver state instead of the simulator |
| 5 | Fare estimates are generated from **string hashing**, not real distance/time. | `RideManager.swift` `estimateFor(pickup:dropoff:)` ~791 | 2–3 days if a routing/maps API is already available; longer if not |
| 6 | Payment failures are **silently swallowed** (`print()` only, no retry, no rider-facing error, no flag on the ride record). | `RideManager.swift` `chargeRiderForRide` ~1237 | 1–2 days |
| 7 | Identity verification (Stripe Identity) and background checks (Checkr) are **fully stubbed client-side, including in Release builds**, and there is **no server-side integration at all** for either. A driver can sign up with zero real vetting. | `Features/SignUp/IdentityVerificationView.swift` ~128-136, `BackgroundCheckView.swift` ~133-143 (note: `started = true` is set unconditionally at line 142, outside the if/else); confirmed absent server-side in `rydr-backend` and `stripe-backend` | 1–2 weeks (real Checkr + Stripe Identity server integration + webhook handling + client wiring) |
| 8 | **No driver approval workflow.** Nothing ever writes `backgroundCheckPassed`/`backgroundCheckStatus`; only path to approval is manually editing Firestore, per the team's own `BETA_TESTING_CHECKLIST.md:23-36`. | App-wide / needs new admin tooling or at minimum a Cloud Function + simple internal screen | 3–5 days for a bare-minimum internal approval screen |
| 9 | Wallet/earnings screen **fabricates financial data** (hardcoded "Chase Checking," $842.78 balance, fake payout history) whenever real fields are missing — which is always right now. | `DriverWalletPayoutsView.swift` ~589-606 | 1–2 days once real payout data is flowing from #8/#2 |
| 10 | License/registration/insurance photos are picked in the UI but **never uploaded anywhere**; the screen falsely claims they're "encrypted in transit and verified." | `DriverLicenseView.swift` ~88-92 and vehicle info upload screens | 2–3 days (wire to Firebase Storage + backend record) |
| 11 | Driver ratings and safety/incident reports are **never persisted**. "Report an incident" shows a static alert with no backend call at all. | Rider: `RideInProgressView.swift` ~92-115, `EndRideView.swift` `submitFeedback()` ~499; Driver: rating UI similarly disconnected | 2–4 days |
| 12 | `rydr-backend` has **no auth middleware at all** — `/chat`, `/community`, `/driver/wait-time-events`, `/driver/account-deletion-requests` are wide open. | `rydr-backend/src/middleware/` (empty), `src/routes/*` | 1–2 days |
| 13 | Firestore rule `driver_status/{uid}`: `read: if signedIn()` exposes **every driver's live location** to any signed-in user, not just matched ride participants. | Firestore rules file | Half day |
| 14 | Stripe secret committed to git history in `stripe-backend/.env` (removed in a later commit but recoverable from history). | git history | Rotate the key — 1 hour, do it regardless of severity |
| 15 | No **account deletion** path found anywhere in the rider app; Apple requires in-app account deletion for apps with account creation — this can block App Store submission entirely, separate from the beta. | Rider app-wide (grep returned nothing); Driver app version exists but is broken (`requestAccountDeletion` always throws `URLError(.badURL)` due to missing `RYDR_BACKEND_BASE_URL` in Info.plist) | 1–2 days both apps |

---

## P1 — Major gaps (fine for a small hand-picked beta, not for public)

| # | Issue | Where | Effort |
|---|---|---|---|
| 16 | No rate limiting on any backend service, including unauthenticated promo-code endpoints (brute-forceable). | `rydr-bank-service/server.js` ~538/577, all services | 1 day |
| 17 | No crash reporting/monitoring on any Node service (no Sentry, no `uncaughtException` handler) — a stray throw kills the process silently. | `stripe-backend`, `rydr-backend`, `rydr-bank-service` | 1 day per service |
| 18 | Crashlytics wired client-side but **no dSYM upload build phase** — crashes arrive unsymbolicated. | RydrDriver `project.pbxproj` | Half day |
| 19 | Push notifications for ride-state transitions are just `// TODO` comments; token registration is real but nothing is ever sent. `aps-environment` is also still `development` in entitlements. | `DriverDashboardVM.swift` (`markArrivedAtPickup`, `startPassengerRide`) | 2–3 days |
| 20 | Saved-cards race condition: hardcoded mock Visa/Mastercard show as "selected" before real Stripe cards load asynchronously. | `RideManager.swift` ~402, `loadRealPaymentMethods()` ~1215 | 1 day |
| 21 | Two divergent `stripe-backend` folders — `RydrDriver/stripe-backend/` is dead/stale, only the repo-root one is live. Risk of someone editing or deploying the wrong one. | Delete `RydrDriver/stripe-backend/` | 15 min |
| 22 | `node_modules/` fully git-tracked in root and `stripe-backend` despite `.gitignore`; an AppleDouble shadow file `stripe-backend/._.env` is also tracked — verify it doesn't carry secret bytes, then clean up. | repo-wide | Half day |
| 23 | Driver presence Firestore write has no error handling — a failed write leaves stale online/location state with no recovery. | `DriverDashboardVM.swift` `updateDriverPresence` ~1347 | Half day |
| 24 | Backend base URL hardcoded/duplicated in two places instead of centralized config, with no staging/prod split. | `PayoutsSetupView.swift:282`, `DriverWalletPayoutsView.swift:13` | Half day |
| 25 | Stray `http://localhost:3000` left in a rider feature — will silently fail in production builds. | `Features/Profile/CommunityView.swift` | 15 min |

---

## P2 — Minor / polish

- Five overlapping, redundantly-written ride-type fields (`qualifiedRideTypes`, `supportedRideTypes`, `selectedRideTypes`, `rideTypes`, `approvedRideTypes`) — refactor debt.
- `vehicleYear` collected but never used in eligibility logic.
- No automated UI test coverage.
- Stray `._*` AppleDouble junk files in Features/Auth, SignUp, Payments — gitignore and clean up.
- No deployment IaC (`render.yaml`/`Procfile`) committed for any backend — config lives only in the Render dashboard.

---

## What this means for August 1

The P0 list is not a weekend's work — items #4 (rider ride-lifecycle rewire) and #7 (real identity/background-check integration) alone are multi-week efforts done properly. Realistic paths from here:

1. **Keep Aug 1, shrink the beta.** Run a closed beta with a handful of hand-vetted drivers (approved manually, as the team's checklist already assumes) and friends/family riders, with explicit internal awareness that payments, ride tracking, and vetting are not yet production-grade. Fix P0 #1, #2, #3, #12, #13, #14 first (these are the ones that create real security/financial exposure even in a small beta) before anyone outside the team touches it.
2. **Slip the date for a public beta.** Treat this punch list as the actual scope, sequence P0 items by team capacity, and set a realistic date once #4 and #7 have effort estimates from whoever will build them.

Either way, items #1–#3 and #12–#14 (backend auth, live keys, idempotency, Firestore privacy rule, leaked secret) should be fixed regardless of which path is chosen — they're exploitable today even by accident, not just at scale.
