# Rydr Backend Contracts Needed For Driver Beta

These routes belong in the main Rydr Backend, not the Stripe backend and not the RydrBank backend.

## Driver Wait Time Event

`POST /driver/wait-time-events`

The iOS driver app calls this route when paid wait time starts or is recorded. If the route is unavailable, the app continues locally and keeps Firestore ride state updated.

Request body:

```json
{
  "rideId": "ride_123",
  "driverId": "driver_uid",
  "riderId": "rider_uid",
  "stage": "pickup",
  "paidWaitSeconds": 0,
  "complimentaryWaitSeconds": 180,
  "recordedAtISO8601": "2026-06-13T23:00:00Z"
}
```

Allowed `stage` values:

- `pickup`
- `stop`

Backend responsibilities:

- Validate the driver is assigned to the ride.
- Recalculate wait time server-side from authoritative timestamps.
- Store wait fee ledger entries without charging twice.
- Expose the resulting fare/earnings adjustments to rider and driver apps.

## Driver Account Deletion Request

`POST /driver/account-deletion-requests`

The iOS driver app calls this route when a driver requests account deletion. If the route is unavailable, the app writes `accountDeletionRequests/{uid}` in Firestore as an alpha/beta fallback.

Request body:

```json
{
  "uid": "driver_uid",
  "email": "driver@example.com",
  "requestedAtISO8601": "2026-06-13T23:00:00Z",
  "source": "ios-driver"
}
```

Backend responsibilities:

- Verify the authenticated user owns the account.
- Disable online driver presence.
- Cancel outstanding ride listeners/dispatch eligibility.
- Preserve legally required trip/payment records.
- Delete or anonymize non-retained profile data.
- Trigger Firebase Auth account deletion through an admin process.
