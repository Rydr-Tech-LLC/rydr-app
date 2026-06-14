# Rydr Driver Controlled Beta Checklist

This checklist is for controlled beta testing only. It is not an App Store production readiness checklist.

## Manual Setup Required

### Apple / Xcode

- Confirm the active beta scheme builds the real driver app target.
- Confirm the bundle identifier is `Rydr-Tech-LLC.Rydr-Drivers`.
- Confirm the Apple Developer team can sign that bundle identifier.
- Create or refresh the provisioning profile for TestFlight.
- Archive one Release build from Xcode and upload it to TestFlight.

### Firebase

- Confirm `GoogleService-Info.plist` belongs to the Firebase iOS app with bundle id `Rydr-Tech-LLC.Rydr-Drivers`.
- Register any App Check debug tokens used by local simulator testing.
- Validate App Check on a real TestFlight device with App Attest / DeviceCheck enabled.
- Confirm Firestore rules allow approved beta drivers to read their own driver document, receive assigned `rideRequests`, write allowed ride status updates, and use Cash Rydr Hub collections.
- Create required Firestore composite indexes for dashboard and ride listeners if Firebase prompts for them.

### Beta Driver Approval Bypass

For each test driver document in `drivers/{uid}`, set:

```json
{
  "betaTester": true,
  "betaBackgroundCheckBypassEnabled": true,
  "backgroundCheckStatus": "beta_bypassed",
  "backgroundCheckPassed": false
}
```

The app only bypasses the background-check gate when both `betaTester` and `betaBackgroundCheckBypassEnabled` are true. This is intended for controlled testing only.

### Driver Rate / Eligibility Seed Data

Each beta driver should have at least:

```json
{
  "selectedRideTypes": ["Rydr Go"],
  "rideTypes": ["Rydr Go"],
  "eligibleRideTypes": ["Rydr Go"],
  "tierRates": {
    "Rydr Go": {
      "perMile": 1.5,
      "perMinute": 0.25
    }
  }
}
```

Adjust values to match current business rules before live testing.

### Stripe Backend

Deploy the Stripe backend separately. Required environment variables:

```bash
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
APP_BASE_URL=https://your-stripe-backend.example.com
PORT=10000
```

Required working routes before payment/payout beta:

- `POST /customers`
- `POST /ephemeral-keys`
- `POST /payment-intents`
- `POST /connect/accounts`
- `POST /connect/account-link`
- `GET /connect/status`
- `POST /identity/session`
- `GET /identity/session/:id`
- `POST /webhook`

Stripe webhook persistence is still required before production payouts. For beta, treat earnings as alpha-recorded unless the backend has been hardened.

### Ride Request Seeding

Until production dispatch exists, create assigned ride requests manually or through the rider app/backend:

```json
{
  "driverId": "<driver uid>",
  "status": "pending",
  "rideType": "Rydr Go",
  "riderName": "Beta Rider",
  "pickupAddress": "Pickup address",
  "dropoffAddress": "Drop-off address",
  "upfrontFare": 18.75
}
```

The app listens for `rideRequests` assigned to the signed-in driver.

## Known Beta Limits

- Driver onboarding uses beta-safe messaging when production Stripe Identity, Checkr, or Connect links are unavailable.
- Push notifications are not implemented; ride state updates rely on Firestore.
- Wait fees are tracked for alpha/beta display but require backend billing hardening.
- Google Maps handoff is not implemented.
- UI tests are currently skipped in the default scheme because that target has package dependency resolution issues.
