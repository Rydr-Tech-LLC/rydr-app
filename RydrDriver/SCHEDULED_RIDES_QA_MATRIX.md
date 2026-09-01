# Scheduled Rides QA Matrix

Shared test-planning reference for the Scheduled Rides feature, spanning Rider
app, Driver app, and Firebase. Product expectations come from
[`../SCHEDULED_RIDES_MVP.md`](../SCHEDULED_RIDES_MVP.md). The Firebase matching
foundation now exists and has emulator coverage; both iOS scheduled-ride
services remain mock-backed and are not integrated with it yet.

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
| Drivers can view and explicitly accept eligible scheduled requests | ⚠️ | Driver map/card flow exists against mocks; `respondToScheduledRide` exists but is not called by the app |
| Confirmed reservations appear in Scheduled Rides | ⚠️ | Reservations UI exists against mocks; real assigned-request and price-lock listeners are missing |
| Conflicting rides cannot be accepted | ⚠️ | Local Driver checks and server schedule-lock transactions exist; end-to-end client coverage is missing |
| Check-in produces a pickup ETA for activation | ⚠️ | Real MapKit ETA calculation exists; Firebase check-in persistence and activation do not |
| Quick Schedule assigns only the first eligible driver | ✅ | Firestore emulator concurrency test passes |
| Choose My Driver admits no more than three offers | ✅ | Firestore emulator concurrency test passes and rider selection creates locks |
| Client writes cannot change protected scheduled data | ✅ | Firestore rules emulator tests deny request, offer, price-lock, and schedule-lock mutations |
| QA covers Rider, Driver, and Firebase behavior | ⚠️ | Firebase foundation coverage exists; real Rider/Driver integration and iOS automated coverage are missing |

## Test scenarios

### Conflicting reservations — ✅ Testable now

- **Layer:** Driver
- **Covers:** `ScheduledRideOpportunity.eligibility(against:)` (accept-time conflict) and `ScheduledRideReservation.checkInEligibility(against:)` (simultaneous check-in)
- **Fixture:** `mock-opp-1` — pickup time deliberately set to overlap `mock-res-1`'s pickup + trip window (see Fixtures below)
- **Steps:** Open Scheduled Rides, tap the `mock-opp-1` pin (labeled with its upfront pay)
- **Expected:** Card shows "Conflicts with your [time] ride," Accept button disabled
- **Also covers:** `mock-res-2` (confirmed, non-conflicting) exists specifically so this is testable directly — check into `mock-res-1`, then attempt Check In on `mock-res-2` → blocked with "Already checked in to your [time] ride"

### Expired opportunities — ✅ Testable now

- **Layer:** Driver
- **Covers:** `ScheduledRideOpportunity.isExpired` / `.eligibility` returning `.expired`
- **Fixture:** `mock-opp-3` — `responseDeadline` deliberately set 10 minutes in the past, so `isExpired` is true immediately on load rather than requiring a real wait
- **Steps:** Open Scheduled Rides, tap the `mock-opp-3` pin (Sandy Springs, $29.00)
- **Expected:** Card shows "This opportunity has expired," Accept button disabled

### First-come acceptance — ✅ Testable now

- **Layer:** Firebase
- **Coverage:** `firebase-foundation.test.js` creates two eligible driver responses concurrently against one Quick Schedule request
- **Expected:** exactly one response succeeds, the request becomes `confirmed`, and one immutable price lock exists
- **Current result:** passing in the Firestore emulator
- **Remaining integration:** `ScheduledRideService.acceptOpportunity` still assumes success and must call the real callable

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

### App relaunch — 🚧 Blocked

- **Layer:** Driver
- **Why it's trivial today:** mock data is static — a relaunch always reproduces the same 3 opportunities and 2 reservations, so "does state survive a relaunch" isn't a meaningful question yet
- **Becomes real once:** actual Firestore reads replace the mock service, and relaunch needs to correctly re-fetch and re-render whatever the driver's real, possibly-changed state is

### Offline behavior — 🚧 Blocked

- **Layer:** Driver + Firebase
- **Why it can't be tested today:** `ScheduledRideService`'s mock methods never fail — every method is `Task.sleep` then unconditional success. The Rider manager also defaults to mock mode, so there is no real scheduled-ride network call to interrupt yet.
- **Expected once buildable:** `acceptError`/`cancelError`/`checkInError` already exist as the UI-facing failure surfaces (see `ScheduledRidesDashboardVM`) — a real network failure should route into those same alerts, not a new mechanism

## Test fixtures

Fixtures live in `ScheduledRideService.swift`'s mock data today. Documenting what each one is *for*, since that's what makes a fixture useful rather than just sample data.

| Fixture | What it's for | Status |
| --- | --- | --- |
| `mock-opp-1` (Rydr Go, $38.00, Midtown → Airport) | Deliberately overlaps `mock-res-1`'s time window — exercises the conflict-eligibility state | ✅ exists |
| `mock-opp-2` (Rydr XL, $24.50, Downtown → Stadium) | The clean/eligible baseline case — no conflicts, not expired | ✅ exists |
| `mock-res-1` (Rydr Go, $42.00 locked, Buckhead → Airport, confirmed) | Baseline confirmed reservation — used both as the conflict target for `mock-opp-1` and for exercising Cancel / Check In | ✅ exists |
| `mock-opp-3` (Rydr Go, $29.00, Sandy Springs → Perimeter) | `responseDeadline` set 10 minutes in the past — exercises `.expired` immediately, no real-time wait needed | ✅ exists |
| `mock-res-2` (Rydr Go, $31.00 locked, Sandy Springs → Downtown, confirmed) | Pickup time clear of every other fixture's window — exercises the "already checked in to a different ride" block without first manually accepting an opportunity | ✅ exists |

