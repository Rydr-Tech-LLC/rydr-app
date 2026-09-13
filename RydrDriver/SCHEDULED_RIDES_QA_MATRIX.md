# Scheduled Rides QA Matrix

Shared test-planning reference for the Scheduled Rides feature, spanning Rider
app, Driver app, and Firebase. Product expectations come from
[`../SCHEDULED_RIDES_MVP.md`](../SCHEDULED_RIDES_MVP.md). The Firebase matching
foundation now exists and has emulator coverage. The Driver app's read and
accept paths are now written against the real listeners and callables (still
fixture-driven in DEBUG, since nothing is deployed); Driver check-in/cancel and
the Rider service remain mock-backed.

Baseline verified on September 1, 2026: `Rydr_Firebase/functions/npm test`
completed with 8/8 tests passing, including Firestore transaction and rules
coverage.


## Status legend

| Status | Meaning |
| --- | --- |
| ✅ Testable now | Real logic and a meaningful local/emulator test path exist |
| ⚠️ Partially testable | UI or backend logic exists, but the end-to-end client path is not wired |
| 🚧 Blocked | Required MVP behavior is not implemented yet |

## Acceptance criteria

| Criterion | Status | Notes |
| --- | --- | --- |
| Drivers can view and explicitly accept eligible scheduled requests | ⚠️ | Full two-step accept implemented: `previewScheduledRideDriverQuote` on selection, `respondToScheduledRide` bound to the returned `quoteFingerprint`. Not yet run against a deployed backend |
| Confirmed reservations appear in Scheduled Rides | ⚠️ | Sorted by soonest pickup, showing `driverPayoutCents` (never the rider's locked fare), with distinct loading / empty / failed / offline states and derived check-in timing badges. Backing collections are not deployed, so DEBUG builds still run on fixtures |
| Conflicting rides cannot be accepted | ⚠️ | Local Driver checks and server schedule-lock transactions exist; end-to-end client coverage is missing |
| Check-in produces a pickup ETA for activation | ⚠️ | Real MapKit ETA calculation exists; Firebase check-in persistence and activation do not |
| Quick Schedule assigns only the first eligible driver | ✅ | Firestore emulator concurrency test passes |
| Choose My Driver admits no more than three offers | ✅ | Firestore emulator concurrency test passes and rider selection creates locks. Driver side reads `selectionMode` off the opportunity and shows "Submit Offer" plus a pre-tap disclosure, so a bid is never presented as a booking |
| Client writes cannot change protected scheduled data | ✅ | Firestore rules emulator tests deny request, offer, price-lock, and schedule-lock mutations |
| QA covers Rider, Driver, and Firebase behavior | ⚠️ | Firebase foundation coverage exists; real Rider/Driver integration and iOS automated coverage are missing |

## Test scenarios

### Conflicting reservations — ✅ Testable now

- **Layer:** Driver
- **Covers:** `ScheduledRideOpportunity.eligibility(against:)` (accept-time conflict) and `ScheduledRideReservation.checkInEligibility(against:)` (simultaneous check-in)
- **Fixture:** `fixture-opp-1` — pickup time deliberately set to overlap `fixture-res-1`'s pickup + trip window (see Fixtures below)
- **Steps:** Open Scheduled Rides, tap the `fixture-opp-1` pin (labeled with its pickup time)
- **Expected:** Card shows "Conflicts with your [time] ride," Accept button disabled
- **Also covers:** `fixture-res-2` (confirmed, non-conflicting) exists specifically so this is testable directly — check into `fixture-res-1`, then attempt Check In on `fixture-res-2` → blocked with "Already checked in to your [time] ride"

### Expired opportunities — ✅ Testable now

- **Layer:** Driver
- **Covers:** `ScheduledRideOpportunity.isExpired` / `.eligibility` returning `.expired`
- **Fixture:** `fixture-opp-3` — `responseDeadline` deliberately set 10 minutes in the past, so `isExpired` is true immediately on load rather than requiring a real wait
- **Steps:** Open Scheduled Rides, tap the `fixture-opp-3` pin (Sandy Springs). No quote is requested for an ineligible opportunity.
- **Expected:** Card shows "This opportunity has expired," Accept button disabled

### First-come acceptance — ✅ Testable now

- **Layer:** Firebase
- **Coverage:** `firebase-foundation.test.js` creates two eligible driver responses concurrently against one Quick Schedule request
- **Expected:** exactly one response succeeds, the request becomes `confirmed`, and one immutable price lock exists
- **Current result:** passing in the Firestore emulator
- **Remaining integration:** the Driver client now calls the real `respondToScheduledRide` with a bound fingerprint; what is left is running it against a deployed backend

### Three-offer limits — ✅ Testable now

- **Layer:** Firebase
- **Coverage:** four eligible drivers respond concurrently to one Choose My Driver request
- **Expected:** exactly three offers succeed, the fourth is rejected, and selecting an offer creates immutable price and schedule locks
- **Current result:** passing in the Firestore emulator
- **Remaining integration:** Rider and Driver apps still use legacy mode values and mock offer flows

### Schedule-lock conflicts — ✅ Testable now

- **Layer:** Firebase
- **Coverage:** an assigned driver attempts to accept an overlapping scheduled request
- **Expected:** the overlapping assignment is rejected transactionally
- **Current result:** passing in the Firestore emulator

### Missed check-in — 🚧 Blocked

- **Layer:** Firebase + Driver
- **Depends on:** no-show detection and the resulting compensation/penalty policy — flagged as an open product question in both the MVP doc and the research sprint doc, not answered yet
- **Expected once buildable:** TBD pending that product decision

### App relaunch — ✅ Testable now

- **Layer:** Driver
- **Covers:** `startListening` clearing `hasLoadedReservations` / `isShowingCachedData` / `loadError` before re-attaching, so a new session never inherits the previous one's flags
- **Expected:** the sheet renders whatever the server currently returns, including rides cancelled while the app was closed — not last-known state
- **Asserted by:** `testRelaunchResetsStateBeforeReattaching`, `testRelaunchReflectsServerTruthNotLastKnownState`

### Stale reservations — ✅ Testable now

- **Layer:** Driver
- **Covers:** `ScheduledRideReservation.timing(now:)` — a friendly sub-state derived from the canonical status plus the clock, which the contract permits ("the UI may derive friendly sub-states from a canonical status") and which persists nothing
- **Why it's needed:** `advanceScheduledRideDeadlines` runs only once a minute, so a reservation can legitimately still read `confirmed` while its check-in window is already open. Without deriving, the driver is told to wait for a window they are inside
- **Expected:** `CHECK IN NOW` inside the window, `CHECK-IN MISSED` past the deadline, and a dimmed `NEEDS ATTENTION` row once pickup time passes with no progress
- **Windows:** `checkInOpensAt = pickup − 60m`, `checkInDeadlineAt = pickup − 50m`, from the approved `driverCheckInLeadMinutes` / `driverCheckInGraceMinutes`

### Stale quote — ✅ Testable now

- **Layer:** Driver
- **Covers:** the `QUOTE_CHANGED` recovery and its local twin, an expired fingerprint
- **Fixture:** `ScheduledRideService.acceptFailing(with: .quoteChanged, repricedQuote:)` — the second quote preview returns the new price, mirroring a real re-quote
- **Expected:** card moves to `.repriced`, shows the **new** `driverPayoutCents`, button reads "Accept $X", and no assignment occurs until a second explicit tap
- **Also covers:** a fingerprint that expired locally is re-quoted *without* calling `respondToScheduledRide` at all — asserted by `testLocallyExpiredFingerprintRepricesWithoutCallingRespond`
- **Why this needs injection:** `QUOTE_CHANGED` is a server-side race. It requires a pricing change to land between preview and accept, which cannot be staged on demand even against a working backend.

### Offline behavior — ✅ Testable now

- **Layer:** Driver + Firebase
- **Covers:** Firestore's `snapshot.metadata.isFromCache`, carried through the listener seam on `ScheduledRideSnapshot` so the flag can never be rendered against a different delivery's data. Listeners use `includeMetadataChanges: true`, so returning online is itself an event rather than something learned on the next document change
- **Expected:** the reservations sheet keeps showing the cached rides — they are real — under a "Showing saved rides — you're offline" banner. Cached data is not an error and must not empty the list
- **Fixture:** `ScheduledRideService.fixtureBacked(isFromCache: true)`
- **Read-path failures** are separately covered: `failingListeners(error:)` lands in `loadError` as driver-readable text rather than a raw Firestore message.
- **Also unblocked:** the accept write path. `acceptFailing(with: .temporaryBackendFailure)` and `quotePreviewFailing(with:)` drive the real classification code, so `acceptError` and the card's `.failed` state are both reachable.
- **Still blocked:** `cancelReservation` is still `Task.sleep` then unconditional success, so `cancelError` cannot be reached yet. Unblocks when it calls the real callable.

### Dispatch lock suppression — 🚧 Blocked

**Run this first once activation is deployed.** It is the only test that catches a silent failure described below.

- **Layer:** Driver + Firebase
- **Covers:** `driver_status/{driverId}.scheduledRideDispatchLock` — "While it exists, the driver receives no normal opportunities"
- **Steps:** with the driver online and a scheduled ride due, let `activateScheduledRides` fire, then create a normal ride request targeting the same driver
- **Expected:** the normal request does not appear; the scheduled handoff does, labelled "Scheduled ride — fare already locked"; the dashboard reads "Heading to your [time] pickup in [area]"
- **Why it needs a deliberate test:** the Driver client's lock decoder is written against *proposed* field names — nothing writes that document yet, so unlike the opportunity/request/offer decoders it could not be verified against `Rydr_Firebase/functions/src/scheduledRides/service.ts`. If the real keys differ, `ScheduledRideDispatchLock` decodes to `nil`, suppression silently never happens, and the dashboard looks completely normal. There is no error and no empty state to notice.
- **Also unverified for the same reason:** `activationAt`, `checkedInAt` and `pickupEtaSeconds` on the request document, since `checkInScheduledRide` is not implemented server-side either
- **Client-side coverage that exists now:** `ScheduledRideDispatchTests` proves the suppression rules and the lock decoder against a hand-built document — what it cannot prove is that the document matches what the server will write

## Test fixtures

Fixtures live in `ScheduledRideFixtures.swift`, inside `#if DEBUG` so they cannot reach a release build. They reach the app through `ScheduledRideService`'s injectable listener closures — `ScheduledRideService.fixtureBacked()` — rather than by living inside the service itself, so the same data drives both the simulator and `RydrDriverTests/ScheduledRideListenerTests.swift`.

Documenting what each one is *for*, since that's what makes a fixture useful rather than just sample data. `testQAFixtureSetCoversEveryEligibilityState` asserts these purposes hold, so a "cleanup" that breaks one fails the suite instead of silently reducing coverage.

| Fixture | What it's for | Status |
| --- | --- | --- |
| `fixture-opp-1` (Rydr Go, $38.00, Midtown → Airport) | Deliberately overlaps `fixture-res-1`'s time window — exercises the conflict-eligibility state | ✅ exists |
| `fixture-opp-2` (Rydr XL, $24.50, Downtown → Stadium) | The clean/eligible baseline case — no conflicts, not expired | ✅ exists |
| `fixture-res-1` (Rydr Go, $42.00 locked, Buckhead → Airport, confirmed) | Baseline confirmed reservation — used both as the conflict target for `fixture-opp-1` and for exercising Cancel / Check In | ✅ exists |
| `fixture-opp-3` (Rydr Go, $29.00, Sandy Springs → Perimeter) | `responseDeadline` set 10 minutes in the past — exercises `.expired` immediately, no real-time wait needed | ✅ exists |
| `ScheduledRideService.neverAnswering()` | Listeners that attach and never answer — the only way to see the sheet's loading state, since fixtures otherwise resolve instantly and real Firestore resolves too fast to catch by hand | ✅ exists |
| `fixtureBacked(isFromCache: true)` | Reproduces an offline launch: Firestore answering from disk with real but possibly-behind data | ✅ exists |
| `ScheduledRideDriverQuote.fixture()` (base $24.50 → payout $17.15) | The driver-quote half of accept. Payout defaults to 70% of base, matching the contract's `driverPayoutBasisPoints` of 7000, so fixture money has the same shape as real money | ✅ exists |
| `fixture-opp-2` carries `selectionMode: .chooseDriver` | The only Choose My Driver fixture. Makes the "Submit Offer" button wording, the pre-tap disclosure, and the offer-submitted terminal state reachable without hand-editing fixtures. The other two are `.quick` | ✅ exists |
| `ScheduledRideSequencedReservations` | Emits a *second* snapshot on demand. `respondToScheduledRide` only acks, so the confirmed reservation arrives on a later listener snapshot — the single-emission fixtures cannot express that | ✅ exists |
| `acceptFailing(with:)` / `quotePreviewFailing(with:)` | Produce a chosen `details.reason` on demand — `QUOTE_CHANGED`, `SCHEDULE_CONFLICT`, `WINDOW_CLOSED`. These are server-side races that cannot be staged against a live backend | ✅ exists |
| `fixture-res-2` (Rydr Go, $31.00 locked, Sandy Springs → Downtown, confirmed) | Pickup time clear of every other fixture's window — exercises the "already checked in to a different ride" block without first manually accepting an opportunity | ✅ exists |

