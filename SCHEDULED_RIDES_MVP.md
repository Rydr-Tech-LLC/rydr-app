# Scheduled Rides — Final Proposed MVP Workflow

## Authority

This document is the product source of truth for the Scheduled Rides MVP. The
Rider app, Driver app, Firebase implementation, QA plan, and sprint acceptance
criteria must remain consistent with it. If an older comment, mock, or planning
document conflicts with this workflow, this workflow wins.

Technical field names and callable boundaries are maintained in
[`Rydr_Firebase/SCHEDULED_RIDES_IMPLEMENTATION_CONTRACT.md`](Rydr_Firebase/SCHEDULED_RIDES_IMPLEMENTATION_CONTRACT.md).
Approved owner assignments and sprint gates are maintained in
[`SCHEDULED_RIDES_SPRINT_PLAN.md`](SCHEDULED_RIDES_SPRINT_PLAN.md).
Changes to the workflow require team review before implementation.

## 1. Rider creates the request

The rider enters the pickup, destination, future pickup time, ride type, and
payment method, then chooses:

- **Quick Schedule:** Rider approves a maximum base price. The first eligible
  driver to accept becomes the assigned driver.
- **Choose My Driver:** The first three qualified drivers to respond appear as
  driver cards. The rider may select as soon as one offer is available and does
  not need to wait for all three.

Firebase calculates and validates all driver-specific prices. Client
calculations may be used for display, but they are not authoritative.

## 2. Driver eligibility and reservation

A driver is eligible when they:

- Support the requested ride type.
- Meet the rider's vehicle and preference requirements.
- Have no conflicting active or scheduled ride.
- Use rates within the rider's approved maximum.
- Explicitly accept the scheduled reservation.

The confirmed ride appears in a dedicated **Scheduled Rides** section in the
Driver app. Full recurring driver calendars and availability schedules are
outside the initial MVP; accepting the request and creating a schedule lock
establishes availability.

## 3. Price locking

- Quick Schedule locks the exact base price when the first eligible driver
  accepts.
- Choose My Driver locks the selected offer when the rider approves it.
- A later driver-rate change cannot affect a confirmed scheduled ride.
- Normal traffic cannot increase the locked base price.
- Waiting, tolls, added stops, and destination changes remain separately
  disclosed extras.
- Route, pickup-time, or ride-type edits invalidate the assignment and price
  lock and require a new quote.

## 4. Check-in and activation

The driver must check in before pickup. At check-in, the Driver app calculates
the pickup ETA using MapKit and sends it to Firebase.

`activation time = scheduled pickup - travel ETA - configurable 5–7 minute buffer`

At activation:

- The driver stops receiving normal ride requests.
- The scheduled pickup becomes their next destination.
- Firebase creates a targeted standard `rideRequests` record containing the
  locked fare.
- The driver accepts or declines through the existing dispatch flow.
- Acceptance continues into the existing rides, navigation, arrival, waiting,
  cancellation, trip, and payment systems.
- Declining or failing to respond immediately begins replacement matching.

## 5. Cancellation and replacement

There is no separate scheduled-reservation cancellation fee. Before
activation, rider cancellation is free. After activation, the existing policy
applies when the driver is two minutes or less from pickup or already waiting:
the current 20% cancellation fee and booking-fee rules remain unchanged.

If a driver cancels:

- Firebase begins priority matching among qualified nearby drivers.
- Automatic replacement is allowed only if the rider approved it during
  booking and the replacement remains within the original pickup window,
  vehicle requirements, preferences, and maximum price.
- For Choose My Driver, any replacement outside those conditions requires
  rider approval.
- If no replacement accepts before the cutoff, the rider may Request Now,
  reschedule, or cancel.

## 6. Firebase changes

Proposed data:

- `scheduledRideRequests`
- `scheduledRideOpportunities`
- `scheduledRideRequests/{id}/offers`
- `scheduledRideRequests/{id}/priceLocks`
- `drivers/{id}/scheduledRideLocks`
- `platformConfig/scheduledRides`

Proposed primary statuses:

`seekingDrivers → awaitingRiderSelection/confirmed → checkInRequired → checkedIn → activating → active → completed`

Exception states:

`replacementSearching`, `replacementApprovalRequired`, `cancelled`, and
`expired`.

Cloud Functions and transactions own request creation, pricing, driver
eligibility, first-accept matching, three-offer limits, selection, schedule
locks, check-in, activation, replacement, cancellation, and expiration.
Firestore Rules prevent clients from directly changing prices, assignments,
deadlines, or protected statuses.

## Dependencies and blockers

- Rate limits currently exist in both iOS apps. Firebase needs one
  authoritative, versioned pricing configuration.
- The check-in design depends on MapKit providing the Driver app's travel ETA
  because Firebase has no server-side routing service today.
- Stripe currently has no scheduled payment hold.
- Deadline and reminder values must be configurable and approved before
  rollout.
