# Scheduled Rides MVP implementation contract

Status: approved implementation baseline as of September 1, 2026. Ashank owns
product/backend approval. Runtime deployment remains disabled until the sprint
acceptance gates and end-to-end tests pass.

Product authority: [`../SCHEDULED_RIDES_MVP.md`](../SCHEDULED_RIDES_MVP.md).
The existing data model and security boundary are described in
[`SCHEDULED_RIDES_DATA_CONTRACT.md`](SCHEDULED_RIDES_DATA_CONTRACT.md).

Changes to money ownership, automatic replacement constraints, cancellation
policy, or the standard-dispatch handoff require Ashank's approval. Other
contract changes require review by the backend owner and the affected client
owner before implementation.

## Production deployment baseline

Read-only Firebase Console audit completed September 1, 2026 for project
`rydrapp-c7ec1`:

- None of the 13 deployed Functions are Scheduled Rides Functions.
- None of the proposed Scheduled Rides collections or
  `platformConfig/scheduledRides` exist in production.
- Deployed Firestore Rules contain no Scheduled Rides rules.
- None of the six deployed composite indexes target Scheduled Rides.

No Firebase resources were changed during this audit. Scheduled Rides must
remain undeployed until the implementation gates below are satisfied and
the team deliberately approves a disabled-first deployment.

## Non-negotiable ownership rules

- Rider and Driver clients submit intent through callable Functions. They do
  not directly create or mutate scheduled requests, offers, assignments,
  price locks, schedule locks, deadlines, or protected statuses.
- Firebase owns driver-specific pricing, eligibility, offer limits,
  assignment, immutable locks, check-in state, activation, replacement,
  cancellation, and expiration.
- Money uses integer USD cents. Dates use Firestore UTC timestamps. The
  booking's IANA time zone is retained as `originalTimeZone`.
- Client calculations are display-only. A value approved or displayed as
  authoritative must originate from Firebase.

## Canonical enums

| Concept | Canonical value | Legacy client value to remove/translate |
| --- | --- | --- |
| Quick Schedule | `quick` | Rider: `quickSchedule` |
| Choose My Driver | `chooseDriver` | Rider: `chooseMyDriver` |
| Seeking drivers | `seekingDrivers` | Rider: `pendingOffers` |
| Rider selecting | `awaitingRiderSelection` | Rider: `awaitingRiderChoice` |
| Confirmed | `confirmed` | Rider: `priceLocked` for Quick Schedule |
| Check-in required | `checkInRequired` | Not implemented in Rider |
| Checked in | `checkedIn` | Driver-only local state today |
| Activating | `activating` | Not implemented in clients |
| Active | `active` | Handoff to the standard ride lifecycle |
| Completed | `completed` | Standard ride lifecycle completion |
| Replacement search | `replacementSearching` | Rider: `driverCancelledFindingReplacement` |
| Replacement approval | `replacementApprovalRequired` | Not implemented in clients |
| Cancelled | `cancelled` | Rider: `cancelledByRider` / `cancelledNoDrivers` |
| Expired | `expired` | Rider value already matches |

The UI may derive friendly sub-states from a canonical status and selection
mode, but it must not persist new status strings.

## Canonical money fields

| Field | Meaning | Visible to |
| --- | --- | --- |
| `minimumQuoteCents` | Server-calculated low end shown during rider review | Rider |
| `approvedMaximumCents` | Maximum base fare approved by the rider | Rider; opportunity eligibility input |
| `approvedReplacementBaseFareCents` | Exact changed replacement fare explicitly approved by the rider; absent for automatic replacement | Rider and server |
| `exactBaseFareCents` | Driver-specific rider base fare on an offer | Rider; selected driver as trip context |
| `driverPayoutCents` | Driver payout from the server quote | Driver |
| `platformShareCents` | Server-calculated platform share | Server/admin |
| `lockedBaseFareCents` | Immutable selected rider base fare in the active versioned price lock | Rider and assigned driver |

`approvedMaximumCents` and `lockedBaseFareCents` are not driver payout. The
Driver app must display `driverPayoutCents` when asking a driver to accept.

## Approved callable boundary

All callable mutations require Firebase Authentication. Mutation callables use
an `operationId` when the request ID alone is not an idempotency key. Errors use
Firebase callable codes plus a stable `details.reason` from the error table
below; clients must branch on the reason rather than message text.

### `previewScheduledRidePrice`

Rider input:

- `requestId`
- `selectionMode`
- `rideType`
- `pickup` (`address`, `latitude`, `longitude`, coarse `area`)
- `destination` (same shape)
- `routeEstimate` (`distanceMiles`, `durationMinutes`, `source`, `version`)
- `scheduledAtEpochMs`
- `timeZone`
- `preferences`

Output remains `{ rideType, pricingVersion, minimum, maximum }`. Each quote is
the complete server quote; `maximum.riderBaseFareCents` is the only approved
maximum the Rider app may pass to creation.

### `createScheduledRideRequest`

Uses the preview payload plus `paymentMethodId` and the exact current
`approvedMaximumCents`. Firebase validates that the payment method belongs to
the rider but does not place a Stripe hold. It atomically creates the private
request and redacted opportunity. Success returns `requestId`, canonical
`status`, `approvedMaximumCents`, and optional `idempotent`.

The booking payload includes `preferences.allowAutomaticReplacement`. Exact
payment details never enter the opportunity projection.

### `previewScheduledRideDriverQuote`

Driver input is `requestId`. A replacement candidate also sends fresh MapKit
`pickupEtaSeconds`, `etaCalculatedAtEpochMs`, and `etaSource`.

Firebase revalidates eligibility, rates, active/scheduled conflicts, offer
capacity, and the rider maximum. Success returns:

- `requestId`
- `quoteFingerprint`
- `exactBaseFareCents`
- `driverPayoutCents`
- `currency`
- `pricingVersion`
- `expiresAtEpochMs`

The fingerprint binds the request, driver, price, rates, pricing version, and
expiry. It is valid for five minutes or until the opportunity closes,
whichever happens first. The Driver UI displays `driverPayoutCents`; it does
not describe the rider maximum as driver earnings.

### `respondToScheduledRide`

Approved input is `requestId` plus the current `quoteFingerprint`. Firebase
recomputes and revalidates the quote in the assignment transaction. A changed
or expired quote returns `QUOTE_CHANGED` so the Driver app must show the new
payout and require another explicit acceptance.

Quick Schedule atomically assigns the first eligible driver. Choose My Driver
creates no more than three active offers. The current foundation accepts only
`requestId`; adding the quote-preview binding is a Sprint 1 implementation
requirement.

### `selectScheduledRideOffer`

Rider input is `requestId` and `offerId`. Firebase revalidates the driver,
quote, deadline, and conflicts, then creates the initial immutable `v1` price
lock and schedule locks. Success returns `requestId`, `offerId`, `confirmed`,
and `lockedBaseFareCents`.

### `checkInScheduledRide`

Assigned-driver input is `requestId`, `operationId`, `pickupEtaSeconds`,
`etaCalculatedAtEpochMs`, and `etaSource = mapKit`. Firebase accepts only a
fresh ETA during the approved check-in window and stores the ETA metadata, not
the driver's submitted location.

Success returns `status = checkedIn`, `activationAtEpochMs`, and the accepted
ETA. Activation is calculated as:

`max(server now, scheduled pickup - pickup ETA - activation buffer)`

### `cancelScheduledRide`

Authenticated rider or assigned-driver input is `requestId`, `operationId`,
and a bounded `reasonCode`. Firebase determines the actor and phase.

- Rider cancellation before activation is free and releases all active locks.
- After activation, cancellation is sent through the standard ride lifecycle.
- The current 20% cancellation fee plus booking-fee rule applies when the
  driver is at pickup, waiting, or has a fresh pickup ETA of 120 seconds or
  less. The backend, not either client, evaluates that evidence.
- Driver cancellation starts replacement matching and never charges the rider
  before a replacement is activated.

### `approveScheduledRideReplacement`

Rider input is `requestId`, `offerId`, `quoteFingerprint`,
`approvedReplacementBaseFareCents`, and `operationId`. This interface is used
only for `replacementApprovalRequired`. Firebase requires the approved cents
to exactly match the disclosed offer, then revalidates the quote, preferences,
arrival estimate, and conflicts before replacing the assignment and creating
the next immutable price-lock version.

## Approved job boundary

| Job | Schedule and responsibility |
| --- | --- |
| `advanceScheduledRideDeadlines` | Every minute; close offer/selection windows, enter `checkInRequired`, detect missed check-in, expire terminal requests, and release unused locks idempotently |
| `activateScheduledRides` | Every minute; activate due checked-in reservations, create the targeted standard request, and acquire the Driver dispatch lock in one idempotent transaction |
| `processScheduledRideReplacements` | Every minute and event-triggered after driver cancel/decline/miss; rank eligible nearby drivers, enforce replacement consent/window/price rules, and stop at the cutoff |
| `sendScheduledRideReminders` | Every five minutes; emit each configured reminder once using a server event ledger |

Each job uses deterministic document IDs or event keys. A retry must not create
a second offer, price lock, schedule lock, notification, or standard ride.

## Standard dispatch handoff

Activation creates `rideRequests/{requestId}` with the same ID as the scheduled
request and sets `resultingRideId = requestId`. The targeted request uses the
existing standard dispatch lifecycle with these required fields:

| Standard request field | Approved source/value |
| --- | --- |
| `status` | `pending` |
| `source` | `scheduledRydr` |
| `riderId`, `driverId`, rider display snapshot | Private scheduled request and current rider profile |
| Pickup/drop-off text and coordinates | Exact private scheduled request values |
| `rideType`, route estimate, preferences | Confirmed scheduled snapshot |
| `scheduledRideRequestId` | Scheduled request ID |
| `scheduledPriceLockId` | Current immutable lock ID |
| `pricingSource` | `scheduledPriceLock` |
| Locked quote fields | Current price-lock quote, including ride subtotal, booking fee, base fare, payout, platform share, currency, and pricing version |
| `expiresAt` | Server activation time plus 18 seconds |

The activation transaction writes a backend-owned
`driver_status/{driverId}.scheduledRideDispatchLock` containing the scheduled
request, standard request, and expiry. While it exists, the driver receives no
normal opportunities. Acceptance enters the existing `rides`, navigation,
arrival, wait, cancellation, completion, and payment flows. Decline, timeout,
or failure clears the lock and begins replacement.

The financial backend must honor the locked ride subtotal and booking fee for
the base fare. Traffic or later rate changes cannot recalculate them. Waiting,
tolls, added stops, and destination changes use separately itemized server
calculations. No second ride lifecycle may be created.

## Replacement and edit decisions

- Automatic replacement requires the rider's booking consent, an arrival no
  later than 15 minutes after the original pickup time, matching vehicle and
  preferences, and a base fare at or below the approved maximum.
- A replacement candidate supplies a fresh MapKit ETA during quote preview;
  Firebase validates freshness and bounds because no server routing service is
  available in the MVP.
- Quick Schedule never auto-assigns outside those conditions. If no compliant
  replacement exists, the rider sees Request Now, reschedule, and cancel.
- Choose My Driver may enter `replacementApprovalRequired` for a disclosed
  out-of-window or otherwise changed offer. Explicit rider approval may create
  a new price lock, including a disclosed fare above the original maximum;
  Firebase never mutates the original maximum or an earlier lock.
- Replacement locks are `v2`, `v3`, and so on, with
  `supersedesPriceLockId`; the request points to the current lock. Assignment
  and schedule-lock transfer are transactional.
- Route, pickup-time, ride-type, stop, or destination edits are not in-place
  mutations before activation. The Rider app cancels free, obtains a new
  quote, and creates a new request ID. After activation, the existing ride
  lifecycle handles disclosed extras.

## Payment decision

The MVP does not create an advance Stripe authorization or hold. Firebase
validates payment-method ownership at booking and again immediately before
activation. If it is unavailable before activation, Firebase cancels the
scheduled request with `paymentMethodUnavailable`, charges no fee, releases
locks, and notifies both parties. Normal post-trip charging remains owned by
the existing payment system.

## Stable callable error map

| Firebase code | `details.reason` | Client action |
| --- | --- | --- |
| `unauthenticated` | `SIGN_IN_REQUIRED` | Require sign-in |
| `invalid-argument` | `INVALID_INPUT` | Show field-level validation |
| `permission-denied` | `NOT_OWNER`, `NOT_ASSIGNED_DRIVER`, `DRIVER_NOT_ELIGIBLE`, `NOT_ALLOWLISTED` | Stop the action and refresh authorized state |
| `not-found` | `REQUEST_NOT_FOUND`, `OFFER_NOT_FOUND` | Remove stale local state and refresh |
| `failed-precondition` | `FEATURE_DISABLED`, `INVALID_STATUS`, `WINDOW_CLOSED`, `QUOTE_CHANGED`, `ACTIVE_RIDE_CONFLICT`, `SCHEDULE_CONFLICT`, `PAYMENT_METHOD_UNAVAILABLE`, `ETA_STALE` | Show the mapped recovery and refresh |
| `already-exists` | `REQUEST_ID_IN_USE`, `OPERATION_ALREADY_APPLIED` | Treat an identical operation as idempotent; otherwise regenerate the ID |
| `resource-exhausted` | `OFFER_LIMIT_REACHED`, `REPLACEMENT_CUTOFF_REACHED` | Stop accepting and refresh |
| `aborted` | `CONCURRENT_UPDATE` | Retry once with jitter, then refresh |
| `unavailable` | `TEMPORARY_BACKEND_FAILURE` | Preserve form state and allow retry |

## Ownership map

| Workstream | Owner |
| --- | --- |
| Firebase, shared DTOs, transactions, pricing/payment integration, deployment, and cross-app integration | Ashank |
| Driver opportunity, reservation, check-in, dispatch handoff, and Driver QA | James |
| Rider booking, offers, management, replacement, recovery, and Rider QA | Ene |

## Approved rollout configuration

These values are approved for MVP implementation. They remain remotely
configurable, and `enabled` stays false until the release gate.

| Config field/policy | Approved value | Decision |
| --- | ---: | --- |
| `enabled` | `false` | Disabled-first deployment; enabling requires separate approval |
| `rolloutMode` | `allowlist` | Empty allowlists deny everyone; `public` requires separate approval |
| `allowedRiderIds`, `allowedDriverIds` | Empty until Sprint 4 | Populate named beta accounts before any enablement |
| `schemaVersion` | `1` | Initial scheduled-ride schema |
| `pricingVersion` | `scheduled-rides-v1` | Version every pricing change |
| `allowedRideTypes` | `eco`, `go`, `xl`, `prestine`, `executive` | All current MVP tiers |
| `pricingTiers` | Checked-in `scheduled-rides-v1` cents schedule | Firebase config is authoritative; iOS copies become display-only |
| `maximumOffers` | 3 | Final MVP Choose My Driver limit |
| `minimumLeadMinutes` | 120 | Earliest bookable pickup is two hours away |
| `maximumAdvanceDays` | 30 | Latest bookable pickup is 30 days away |
| `offerWindowMinutes` | 30 | Driver responses close 30 minutes after request creation |
| `riderSelectionWindowMinutes` | 30 | Selection closes 30 minutes after the offer window; rider may choose immediately |
| `driverQuoteValidityMinutes` | 5 | Quote also expires when the opportunity closes |
| `driverCheckInLeadMinutes` | 60 | Check-in opens 60 minutes before pickup |
| `driverCheckInGraceMinutes` | 10 | Deadline is 50 minutes before pickup |
| `checkInEtaMaxAgeMinutes` | 5 | ETA must be fresh when submitted |
| `activationBufferMinutes` | 5 | Approved value within the proposed 5–7 minute range |
| `activationDispatchTimeoutSeconds` | 18 | Reuses the current standard Rider dispatch response window |
| `reservationLeadMinutes` | 60 | Schedule lock begins 60 minutes before pickup |
| `reservationTurnaroundMinutes` | 15 | Schedule lock extends 15 minutes after estimated trip end |
| `scheduleLockBucketMinutes` | 15 | Transactional lock granularity |
| `replacementPickupWindowMinutes` | 15 | Automatic replacement must arrive by pickup plus 15 minutes |
| `replacementCutoffMinutesBeforePickup` | 0 | Automatic matching stops at the scheduled pickup time; then show recovery options |
| `reminderLeadMinutes` | `[1440, 120]` | Send to rider and confirmed driver once each |
| `driverCheckInReminderMinutesBeforePickup` | `[60, 55]` | Check-in opens at 60; second reminder is five minutes before deadline |
| `driverPayoutBasisPoints` | 7000 | Retains the existing 70% driver share of ride subtotal |

The checked-in example now records the approved values, but the current config
parser does not yet enforce every new field. The first implementation sprint
must add parser and emulator coverage before the template is deployed. Until
then, `enabled` must remain false.

`checkInDueAt` in the current foundation is ambiguous. Implementation must
store separate `checkInOpensAt` and `checkInDeadlineAt` timestamps using the
approved lead and grace values.

## Implementation gates before enabling

- Rider, Driver, and Firebase use the canonical enums and DTOs above.
- Every callable returns the approved success shape and stable error reason.
- Driver payout is distinct from rider fare in storage and UI.
- Opportunity cards show coarse pickup area, trip distance/duration, tier, and
  requirements; exact addresses and rider identity appear only after
  assignment.
- Targeted activation passes through the existing dispatch and ride lifecycle.
- Locked-base financial tests cover rate changes, traffic, waiting, tolls,
  stops, destination changes, and the cancellation threshold.
- Emulator concurrency, Security Rules, job retry, offline/relaunch, and both
  iOS end-to-end suites pass.
- Functions, rules, indexes, and disabled config are deployed to the allowlist
  environment before any `enabled = true` change.
