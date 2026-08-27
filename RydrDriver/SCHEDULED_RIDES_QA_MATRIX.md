# Scheduled Rides QA Matrix

Shared test-planning reference for the Scheduled Rides feature, spanning Rider app, Driver app, and Firebase. It reflects what's actually true today. Note that several scenarios below are documented as **not yet testable** as they are dependent on back end components being developped. 


## Status legend

| Status | Meaning |
| --- | --- |
| ✅ Testable now | Real logic exists in the Driver app today; can be exercised and verified |
| ⚠️ Partially testable | Something exists, but the test is trivial or incomplete until a dependency lands |
| 🚧 Blocked | Depends on backend work (Cloud Functions, Firestore emulator, rider-side UI) not built yet |

## Acceptance criteria

| Criterion | Status | Notes |
| --- | --- | --- |
| Drivers can view and explicitly accept eligible scheduled requests | ✅ | Map pins → `ScheduledRideOpportunityCard` → `ScheduledRidesDashboardVM.accept(_:driverId:)` |
| Confirmed reservations appear in Scheduled Rides | ✅ | Accept moves the opportunity into `vm.reservations`, shown in the reservations sheet |
| Conflicting rides cannot be accepted | ✅ | `ScheduledRideOpportunity.eligibility(against:)` — pickup/trip time-window overlap check |
| Check-in produces a pickup ETA for the activation calculation | ✅ | `ScheduledRidesDashboardVM.checkIn(_:driverId:driverCoordinate:)` — real MapKit call via `RideRequestRouteEstimator` |
| QA covers Rider, Driver, and Firebase behavior rather than only Driver UI | 🚧 | Firebase Functions don't exist yet, so their rows below are placeholders, not coverage |

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

### First-come acceptance — 🚧 Blocked

- **Layer:** Firebase
- **Depends on:** the real `respondToScheduledRide` callable and a Firestore emulator running two concurrent driver clients
- **Why it can't be tested today:** this is a Firestore-transaction race condition by definition — two drivers responding to the same Quick Schedule opportunity within the same moment, only one should win. `ScheduledRideService.acceptOpportunity` is a single-client mock with no second driver to race against; it always succeeds.
- **Expected once buildable:** matches the existing `runTransaction` 409 pattern already used by `accept()` for on-demand rides (per the research sprint doc)

### Three-offer limits — 🚧 Blocked

- **Layer:** Firebase
- **Depends on:** Choose My Driver backend logic and the (currently removed) `selectionMode` distinction — deliberately deferred, see Open Items
- **Expected once buildable:** a 4th driver's offer attempt against an already-full `offers` subcollection is rejected

### Missed check-in — 🚧 Blocked

- **Layer:** Firebase + Driver
- **Depends on:** no-show detection and the resulting compensation/penalty policy — flagged as an open product question in both the MVP doc and the research sprint doc, not answered yet
- **Expected once buildable:** TBD pending that product decision

### App relaunch — ⚠️ Partially testable

- **Layer:** Driver
- **Why it's trivial today:** mock data is static — a relaunch always reproduces the same 3 opportunities and 2 reservations, so "does state survive a relaunch" isn't a meaningful question yet
- **Becomes real once:** actual Firestore reads replace the mock service, and relaunch needs to correctly re-fetch and re-render whatever the driver's real, possibly-changed state is

### Offline behavior — 🚧 Blocked

- **Layer:** Driver + Firebase
- **Why it can't be tested today:** `ScheduledRideService`'s mock methods never fail — every method is `Task.sleep` then unconditional success. There's no real network call to interrupt yet.
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

