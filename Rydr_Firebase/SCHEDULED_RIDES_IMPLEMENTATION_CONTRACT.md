# Scheduled Rides MVP implementation contract

Status: pre-sprint contract-freeze checklist. Runtime deployment remains
disabled until the open values below are approved and end-to-end acceptance
tests pass.

Product authority: [`../SCHEDULED_RIDES_MVP.md`](../SCHEDULED_RIDES_MVP.md).
The existing data model and security boundary are described in
[`SCHEDULED_RIDES_DATA_CONTRACT.md`](SCHEDULED_RIDES_DATA_CONTRACT.md).

## Production deployment baseline

Read-only Firebase Console audit completed September 1, 2026 for project
`rydrapp-c7ec1`:

- None of the 13 deployed Functions are Scheduled Rides Functions.
- None of the proposed Scheduled Rides collections or
  `platformConfig/scheduledRides` exist in production.
- Deployed Firestore Rules contain no Scheduled Rides rules.
- None of the six deployed composite indexes target Scheduled Rides.

No Firebase resources were changed during this audit. Scheduled Rides must
remain undeployed until the contract-freeze criteria below are satisfied and
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
| `exactBaseFareCents` | Driver-specific rider base fare on an offer | Rider; selected driver as trip context |
| `driverPayoutCents` | Driver payout from the server quote | Driver |
| `platformShareCents` | Server-calculated platform share | Server/admin |
| `lockedBaseFareCents` | Immutable selected rider base fare in `priceLocks/v1` | Rider and assigned driver |

`approvedMaximumCents` and `lockedBaseFareCents` are not driver payout. The
Driver app must display `driverPayoutCents` when asking a driver to accept.

## Existing callable boundary

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

Output includes canonical ride type, pricing version, minimum quote, and
maximum quote. The Rider app uses these server values for approval.

### `createScheduledRideRequest`

Uses the preview payload plus the exact current `approvedMaximumCents` returned
by Firebase. It atomically creates the private request and redacted
opportunity.

### `respondToScheduledRide`

Driver input is `requestId`. Firebase revalidates the complete eligibility
rule. Quick Schedule atomically assigns the first eligible driver. Choose My
Driver creates no more than three active offers.

Before client integration is complete, the team must freeze how the Driver app
obtains and approves its exact `driverPayoutCents`; accepting based on
`approvedMaximumCents` is not valid.

### `selectScheduledRideOffer`

Rider input is `requestId` and `offerId`. Firebase revalidates the driver and
conflicts, then creates immutable price and schedule locks.

## Required callable and job boundary for the remaining MVP

Names below are proposed interface names and must be frozen in Sprint 0 before
client implementation.

| Interface | Required responsibility |
| --- | --- |
| Driver quote/accept interface | Return the exact driver payout before explicit acceptance and bind acceptance to the current quote/version |
| `checkInScheduledRide` | Validate driver, request, check-in window, and ETA payload; store check-in and activation time |
| `cancelScheduledRide` | Apply free pre-activation cancellation or hand post-activation cancellation to the existing ride policy |
| Activation job | Advance due checked-in reservations, suppress normal dispatch, and create one targeted standard request with locked-fare provenance |
| Replacement transaction/job | Start priority matching on driver cancel/decline/timeout and enforce automatic-replacement constraints |
| Expiration/reminder jobs | Advance deadlines, notify participants, expire requests/offers, and release locks safely |

The targeted standard request must remain compatible with the existing
dispatch and ride lifecycle. Its final field mapping must be reviewed against
the current `rideRequests` contract before Sprint 2; do not create a parallel
ride lifecycle.

## Client ownership map

| Workstream | Owner |
| --- | --- |
| Firebase, shared DTOs, transactions, deployment, integration | Product/backend owner |
| Driver opportunity, reservation, check-in, and dispatch handoff | James |
| Rider booking, offers, management, replacement, and recovery | Ene |

## Configuration requiring approval before rollout

The checked-in example values are implementation defaults, not approved
product policy.

| Setting | Current example | Approval status |
| --- | ---: | --- |
| Minimum scheduling lead | 120 minutes | Pending |
| Maximum scheduling horizon | 30 days | Pending |
| Driver offer window | 30 minutes | Pending |
| Rider selection window | 30 minutes | Pending |
| Check-in lead | 60 minutes | Pending |
| Check-in grace | 10 minutes | Pending |
| Activation buffer | 5 minutes | Pending; MVP permits configurable 5–7 minutes |
| Reservation travel lead | 60 minutes | Pending |
| Reservation turnaround | 15 minutes | Pending |
| Schedule-lock bucket | 15 minutes | Pending |
| Replacement cutoff | Not implemented | Pending |
| Reminder schedule | Not implemented | Pending |

## Contract-freeze exit criteria

- Rider, Driver, and Firebase use the canonical enums above.
- Every callable has an agreed request, success response, and error-code map.
- Driver payout is distinct from rider fare in storage and UI.
- Opportunity redaction and coarse destination visibility are approved.
- The targeted standard request maps into the existing dispatch lifecycle.
- All configuration values above have named approvers and recorded values.
