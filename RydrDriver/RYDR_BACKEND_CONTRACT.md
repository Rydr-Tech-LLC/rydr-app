# Rydr Backend Contracts Needed For Driver Beta

These routes belong in the main Rydr Backend, not the Stripe backend and not the RydrBank backend.

## Driver Wait Time Event

`POST /driver/wait-time-events`

The iOS driver app calls this route when pickup grace wait starts, paid wait starts, or waiting ends. If the route is unavailable, the app continues locally and keeps Firestore ride state updated.

Request body:

```json
{
  "rideId": "ride_123",
  "driverId": "driver_uid",
  "riderId": "rider_uid",
  "waitStage": "pickup_grace_started",
  "complimentarySeconds": 180,
  "paidWaitSeconds": 0,
  "timestamp": "2026-06-13T23:00:00Z"
}
```

Allowed `waitStage` values:

- `pickup_grace_started`
- `pickup_paid_started`
- `stop_paid_started`
- `wait_ended`

Current beta write target:

- `waitTimeEvents/{eventId}`

Backend responsibilities:

- Validate the driver is assigned to the ride.
- Recalculate wait time server-side from authoritative timestamps.
- Store wait fee ledger entries without charging twice.
- Expose the resulting fare/earnings adjustments to rider and driver apps.

## Driver Account Deletion Request

`POST /driver/account-deletion-requests`

The iOS driver app calls this route when a driver requests account deletion. For beta, the backend records the request and does not delete the Firebase Auth user yet.

Request body:

```json
{
  "uid": "driver_uid",
  "role": "driver",
  "email": "driver@example.com",
  "reason": "optional user reason",
  "requestedAt": "2026-06-13T23:00:00Z"
}
```

Current beta write target:

- `accountDeletionRequests/{requestId}`

Backend responsibilities:

- Verify the authenticated user owns the account.
- Disable online driver presence.
- Cancel outstanding ride listeners/dispatch eligibility.
- Preserve legally required trip/payment records.
- Delete or anonymize non-retained profile data.
- Trigger Firebase Auth account deletion through an admin process.
