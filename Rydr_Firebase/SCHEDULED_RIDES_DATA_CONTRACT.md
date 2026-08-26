# Scheduled Rides MVP data contract

Status: implementation candidate; review before Firebase deployment. Schema version: `1`.

## Ownership and invariants

- Rider and Driver apps call Cloud Functions; they never write scheduled-ride documents directly.
- Firebase owns eligibility, quote calculations, offer counts, assignment, price locks, status transitions, and schedule locks.
- Monetary values use integer USD cents. Times use Firestore UTC timestamps; `originalTimeZone` stores the booking's IANA zone for display and daylight-saving interpretation.
- `platformConfig/scheduledRides` is fail-closed: a missing document or `enabled != true` disables all scheduled-ride callables. Optional rider/driver allowlists support a staged rollout.
- A confirmed price lock is immutable. Trip route, pickup time, ride type, stops, or destination changes require a new quote/request. Traffic does not raise the locked base fare; waiting, stops, tolls, and other disclosed extras remain separate.

| Field group | Submitted by | Authoritative owner |
| --- | --- | --- |
| Pickup, destination, pickup time, time zone, ride type, preferences | Rider app | Firebase validates and snapshots |
| Route distance/duration estimate and source version | Rider MapKit integration | Firebase validates bounds and snapshots; server-side route verification remains an integration dependency |
| Driver configured rates and eligibility profile | Driver app / approval workflow | Firebase validates against versioned platform bounds |
| Quotes, approved maximum, offer count/status, assignment, deadlines | None directly | Firebase Functions only |
| Price locks and driver schedule locks | None directly | Firebase transaction only |
| Feature settings and pricing limits | Admin review/deployment | `platformConfig/scheduledRides` |

## Collections

### `scheduledRideRequests/{requestId}`

Private orchestration record. Fields include `schemaVersion`, `riderId`, `selectionMode` (`quick` or `chooseDriver`), `rideType`, exact `pickup`/`destination`, `routeEstimate`, `scheduledAt`, `originalTimeZone`, `preferences`, `status`, `approvedMaximumCents`, `minimumQuoteCents`, `currency`, `pricingVersion`, offer/selection/check-in deadlines, offer counters, selected/assigned driver IDs, `priceLockId`, and eventual `resultingRideId`. MVP preferences are a bounded `requiredCapabilities` list, primitive `requiredVehicleAttributes` map, and `allowAutomaticReplacement` choice.

Primary states: `seekingDrivers`, `awaitingRiderSelection`, `confirmed`, `checkInRequired`, `checkedIn`, `activating`, `active`, `completed`. Exception states: `replacementSearching`, `replacementApprovalRequired`, `cancelled`, `expired`.

### `scheduledRideOpportunities/{requestId}`

Approved-driver browse projection. Contains ride type, scheduled time, route estimate, preferences, approved maximum, deadline, and coarse pickup area/rounded coordinates. It intentionally excludes rider identity, exact addresses, assignment internals, and payment information.

### `scheduledRideRequests/{requestId}/offers/{driverId}`

Server-created offer with a driver/vehicle snapshot, versioned rate snapshot, exact quote, currency, expiration, and status. Quick Schedule creates one selected offer. Choose My Driver transactionally admits the first three valid offers.

### `scheduledRideRequests/{requestId}/priceLocks/v1`

Immutable server-created record of rider, selected driver/offer, route estimate, versioned rates, exact quote, approved maximum, locked base fare, currency, and approval time.

### `drivers/{driverId}/scheduledRideLocks/{UTC-bucket}`

Server-only reservation buckets covering configured travel lead time, estimated ride duration, and turnaround time. Creating every bucket in the assignment transaction prevents overlapping reservations. Recurring availability calendars are outside MVP.

### `platformConfig/scheduledRides`

Feature flag, rollout allowlists, allowed tiers, versioned rate bounds, offer/scheduling/check-in windows, reservation buffers, lock granularity, and payout basis points. See `config/scheduledRides.example.json`; the checked-in example is disabled.

## Callable contracts

- `previewScheduledRidePrice`: validates the planned route and returns the server minimum and maximum base fares.
- `createScheduledRideRequest`: requires the exact current server maximum approved by the rider and atomically creates the private request plus redacted opportunity.
- `respondToScheduledRide`: revalidates driver approval, tier eligibility, active-ride state, configured rates, price ceiling, and conflicts. Quick Schedule atomically assigns the first eligible driver; Choose My Driver atomically caps offers at three.
- `selectScheduledRideOffer`: rider-only selection that revalidates eligibility/conflicts and atomically creates the immutable price and schedule locks.

## Deferred integration work

Check-in, ETA-based activation (`pickup time - travel ETA - configurable buffer`), reminders/expiration, replacement matching/approval, edits/cancellation, standard `rides` activation, payment preflight, notifications, and cleanup/release of locks belong to later sprints. The fields and statuses above reserve that shared path without exposing unsafe client writes now.
