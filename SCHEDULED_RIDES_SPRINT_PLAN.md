# Scheduled Rides MVP sprint assignments

Status: approved delivery plan. The implementation contract was approved on
September 1, 2026. This plan begins after the stabilization PR is merged.

Product authority: [`SCHEDULED_RIDES_MVP.md`](SCHEDULED_RIDES_MVP.md).
Technical authority:
[`Rydr_Firebase/SCHEDULED_RIDES_IMPLEMENTATION_CONTRACT.md`](Rydr_Firebase/SCHEDULED_RIDES_IMPLEMENTATION_CONTRACT.md).

## Cadence and ownership

- Four two-week implementation sprints.
- Ashank owns Firebase, pricing/payment behavior, shared contracts, integration,
  deployment, and the release decision.
- James owns the Driver app and Driver acceptance evidence.
- Ene owns the Rider app and Rider acceptance evidence.
- Client work may use approved fixtures while its backend dependency is under
  review, but a sprint is not complete until the real callable/listener path
  passes.
- Each owner opens focused PRs into `feature/scheduled-rides-integration`.
  Protected data is never written directly by either iOS app.

## Definition of done for every assignment

- Uses the canonical enums, money fields, error reasons, and server ownership
  in the implementation contract.
- Includes automated coverage at the owning layer and updates the shared QA
  matrix when behavior becomes testable.
- Handles loading, empty, stale, retry, permission, and offline states without
  silently falling back to fake success.
- Preserves idempotency and does not weaken Firestore Rules.
- Is reviewed by Ashank for cross-system contract consistency and by the
  affected client owner for UI behavior.

## Sprint 1 — Real booking, offers, and reservation

Goal: replace the mock-only boundary with the real disabled/allowlisted
Firebase foundation for both selection modes.

### Ashank

- **SR-A1:** Add the approved configuration fields, stable callable error
  reasons, shared DTO fixtures, and separate `checkInOpensAt` /
  `checkInDeadlineAt` timestamps.
- **SR-A2:** Implement `previewScheduledRideDriverQuote` and bind
  `respondToScheduledRide` to the five-minute quote fingerprint. Preserve the
  first-accept and three-offer transaction guarantees.
- **SR-A3:** Extend request creation with payment-method ownership validation,
  automatic-replacement consent, and version-ready price locks.
- **SR-A4:** Publish emulator fixtures for Rider and Driver client tests and
  review every client payload against Firestore Rules.

### James

- **SR-J1:** Replace Driver legacy Scheduled Ride DTO names with canonical
  models and add authenticated opportunity/reservation listeners.
- **SR-J2:** Wire the opportunity card to driver quote preview, display only
  `driverPayoutCents` as earnings, and require explicit acceptance with the
  fingerprint.
- **SR-J3:** Back the dedicated Scheduled Rides section with confirmed Firebase
  reservations, including empty, expired, conflict, quote-changed, and relaunch
  states. Keep deterministic mocks injectable for previews and tests only.

### Ene

- **SR-E1:** Replace Rider legacy modes/statuses with canonical DTOs and a
  callable/listener service; remove the direct protected-write path.
- **SR-E2:** Wire booking review to server price preview and request creation,
  including payment method and automatic-replacement consent.
- **SR-E3:** Wire Quick Schedule confirmation and Choose My Driver offer cards,
  immediate selection after the first offer, three-offer maximum, price lock,
  and stale/error recovery.

### Sprint 1 exit gate

- Quick Schedule assigns exactly one driver end to end.
- Choose My Driver displays up to three server offers and allows immediate
  selection.
- Rider sees the server base fare; Driver sees the server payout; neither app
  can mutate protected fields.
- Both apps can relaunch into the same confirmed reservation while the feature
  remains disabled except for emulator/allowlisted testing.

## Sprint 2 — Check-in, activation, and standard dispatch

Goal: move a confirmed reservation into the existing live ride lifecycle
without recalculating its locked base fare.

### Ashank

- **SR-A5:** Implement deadline advancement and `checkInScheduledRide`,
  including the 60-minute opening, 10-minute grace, fresh MapKit ETA validation,
  and idempotent activation time.
- **SR-A6:** Implement `activateScheduledRides`, the targeted standard
  `rideRequests` mapping, the backend-owned Driver dispatch lock, and the
  18-second response deadline.
- **SR-A7:** Update standard financial finalization to honor the locked ride
  subtotal and booking fee while separately calculating waiting, tolls, stops,
  destination changes, and eligible cancellation charges.
- **SR-A8:** Add concurrency/retry tests proving activation creates one standard
  request and that rate or traffic changes cannot alter the locked base fare.

### James

- **SR-J4:** Implement the real Scheduled Rides check-in flow, calculate pickup
  ETA with MapKit, submit it once, and render check-in-required, checked-in, and
  activating states.
- **SR-J5:** Suppress normal opportunities while the server dispatch lock is
  active, make the scheduled pickup the next destination, and present the
  targeted request through the existing accept/decline card.
- **SR-J6:** Hand acceptance into the existing navigation/arrival/wait/trip
  experience and recover correctly after relaunch or a temporary network loss.

### Ene

- **SR-E4:** Build the real confirmed-reservation management view with driver,
  locked fare, pickup time, check-in/activation progress, and notification
  state.
- **SR-E5:** Follow `resultingRideId` into the existing Rider dispatch and trip
  experience without creating a parallel ride screen.
- **SR-E6:** Display locked-base versus separately disclosed extras and the
  post-activation cancellation rule using server state.

### Sprint 2 exit gate

- A checked-in reservation activates at the approved ETA formula and produces
  one targeted standard request.
- The driver receives no normal dispatch while the scheduled dispatch lock is
  active.
- Accept reaches the existing ride lifecycle; decline or 18-second timeout
  produces the replacement trigger.
- Completion retains the locked base under rate and traffic changes.

## Sprint 3 — Cancellation, replacement, reminders, and recovery

Goal: complete every exception path in the final proposed MVP.

### Ashank

- **SR-A9:** Implement `cancelScheduledRide`, free pre-activation Rider
  cancellation, lock cleanup, and the existing 20% plus booking-fee policy at
  the two-minute/waiting threshold after activation.
- **SR-A10:** Implement priority replacement matching, the 15-minute arrival
  window, scheduled-pickup cutoff, automatic-replacement constraints, transactional
  schedule-lock transfer, and versioned replacement price locks.
- **SR-A11:** Implement `approveScheduledRideReplacement`, reminder/expiration
  jobs and event ledger, and payment-method revalidation immediately before
  activation.
- **SR-A12:** Add race, retry, missed-check-in, driver-cancel, payment-failure,
  and no-replacement emulator coverage.

### James

- **SR-J7:** Wire Driver reservation cancellation, missed check-in, activation
  decline/timeout, and replacement opportunity behavior to server results.
- **SR-J8:** Support replacement acceptance, refreshed payout approval,
  reassigned check-in, dispatch-lock cleanup, and normal-dispatch restoration.
- **SR-J9:** Finish Driver reminders, offline/relaunch recovery, duplicate-action
  protection, and actionable error copy for every approved reason.

### Ene

- **SR-E7:** Finish the automatic-replacement booking control and explain its
  price, vehicle/preference, and pickup-window limits.
- **SR-E8:** Build replacement approval cards for Choose My Driver and the
  Request Now, reschedule, and cancel recovery choices when replacement fails
  or reaches cutoff.
- **SR-E9:** Implement free pre-activation cancellation, cancel-and-rebook for
  route/time/type edits, reminder handling, payment-failure recovery, and
  duplicate-action protection.

### Sprint 3 exit gate

- Rider, Driver, deadline, payment, and network failure scenarios end in a
  documented canonical state with correct lock cleanup.
- Automatic replacement never exceeds prior consent; manual replacement
  creates a new immutable price-lock version.
- No replacement after cutoff is silently assigned.
- Every Rider recovery choice behaves as defined by the MVP workflow.

## Sprint 4 — Release hardening and allowlisted beta

Goal: prove the complete system, deploy disabled, and prepare a deliberate
allowlisted enablement decision.

### Ashank

- **SR-A13:** Complete Rules and indexes, job observability, structured audit
  events, alerting, cleanup tooling, rollout metrics, and rollback steps.
- **SR-A14:** Resolve or explicitly risk-accept the Firebase Functions npm
  advisories, then rerun all Firebase, backend, Stripe, and emulator suites.
- **SR-A15:** Deploy functions, rules, indexes, and `enabled = false` config;
  verify production shape, then populate only named Rider/Driver allowlists.
- **SR-A16:** Lead the cross-app acceptance run and record the separate approval
  required before changing `enabled` to true.

### James

- **SR-J10:** Complete Driver unit/UI coverage, accessibility, notification,
  offline, relaunch, clock-skew, low-location-accuracy, and MapKit failure QA on
  supported iOS versions.
- **SR-J11:** Run the full Driver side of the QA matrix on a physical device and
  fix release-blocking defects.

### Ene

- **SR-E10:** Complete Rider unit/UI coverage, accessibility, notification,
  offline, relaunch, daylight-saving/time-zone, payment, and stale-offer QA on
  supported iOS versions.
- **SR-E11:** Run the full Rider side of the QA matrix on a physical device and
  fix release-blocking defects.

### Sprint 4 release gate

- Both iOS apps build and pass on Mac/Xcode and physical devices.
- Emulator, backend, Stripe, Rules, retry/idempotency, and locked-fare tests all
  pass with no unresolved critical/high release risk.
- Production resources exist with Scheduled Rides still disabled by default.
- Named allowlisted accounts pass Quick Schedule, Choose My Driver, check-in,
  activation, cancellation, replacement, completion, and payment acceptance.
- Ashank records a separate go/no-go approval before enabling broader traffic.
