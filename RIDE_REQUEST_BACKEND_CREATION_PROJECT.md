# Project: Backend-Owned Ride-Request Creation

Owner: Riley  
Status: Ready to assign after the matching contract is agreed with Deja  
Suggested level: Junior software engineering student with mentor review  
Primary codebase: `rydr-backend`  
Supporting codebases: Rider app, Firebase Functions, Firestore rules, and Deja's driver-matching service  
Project goal: A rider must not be able to create or alter an authoritative ride request by writing directly to Firestore.

## The assignment in one paragraph

Move standard ride-request creation from the Rider app into an authenticated backend endpoint. The Rider app may submit trip details and identify one candidate returned by Deja's matching service, but it must not choose the rider identity, driver eligibility, price, expiration, lifecycle state, or notification recipient. The backend must verify the caller, payment readiness, match session, selected candidate, and quote; then atomically create the request and its dispatch signal with retry protection. Once the app uses the endpoint, Firestore rules must reject direct client creation of authoritative `rideRequests` and `rideRequestSignals` documents.

## Why this work is needed

The Rider app currently creates the request ID and writes both authoritative documents directly:

- `Features/Booking/FirestoreRideService.swift`, beginning in `requestRide`
- `rideRequests/{rideId}`
- `rideRequestSignals/{rideId}`

The app also supplies identity, driver, route-estimate, display-price, lifecycle, and expiration fields. Firestore rules restrict some financial fields, but a modified client can still attempt to choose the target driver, forge request metadata, create inconsistent request/signal pairs, or bypass the intended matching flow.

The new endpoint makes Firestore a backend-written source of truth while keeping the existing Rider experience: the backend returns eligible driver cards, the rider selects one, and the backend creates the offer.

## Ownership boundary

### Riley owns

- The authenticated standard ride-request creation endpoint
- Firebase ID-token enforcement through the existing backend middleware
- Canonical rider identity lookup
- Backend payment-readiness verification
- Match-session and selected-candidate validation
- Quote-fingerprint validation and repricing response
- Revalidation of the selected driver at request time
- Idempotent, atomic creation of the request and dispatch signal
- Server-controlled status, timestamps, expiration, source, and notification target
- Rider-app migration from direct Firestore writes to the endpoint
- Firestore rule changes that deny direct client creation
- Endpoint, emulator, rules, and client-contract tests
- Documentation of the final request schema and error contract

### Deja owns

- Discovering candidate drivers
- Driver eligibility and presence checks used by matching
- Geographic, ride-type, work-zone, destination, and preference filtering
- Candidate ranking
- Creating or supplying the match session
- Candidate membership in that session
- Match-session expiration and matching-specific exclusions
- The reusable matching interface for immediate and scheduled rides

### Shared contract between Riley and Deja

Before implementation, agree on:

- `matchSessionId` format and storage
- Candidate identifier format
- Session and candidate expiration
- What driver facts must be revalidated when the request is created
- Quote input and output fields
- Quote-fingerprint generation and comparison
- How a stale quote is represented
- How attempted, declined, expired, or unavailable candidates are recorded
- Whether one match session may create only one active request

Riley must not copy Deja's matching algorithm into the request endpoint. The endpoint should call a shared matching service or repository.

## Scope

### Included

- Standard card-ride request creation
- Authenticated backend route
- Payment-readiness check
- Match-session validation
- Selected-candidate revalidation
- Backend quote recalculation using `standard_usd_v2`
- Quote fingerprint and expiration
- Promotion or RydrBank reference validation/reservation handoff
- Replacement-ride reference validation
- Idempotency
- Atomic Firestore writes
- Request expiration
- Driver notification trigger compatibility
- Rider app integration
- Firestore security rules
- Automated tests and local emulator demonstration

### Not included

- Designing Deja's ranking algorithm
- Changing driver pricing policy or the 90/10 split
- Rewriting final ride settlement
- Rewriting the complete ride lifecycle state machine
- Stripe production deployment or live charges
- Cash Rydr Hub requests
- Scheduled-ride orchestration, except keeping the service reusable
- A redesign of Rider or Driver screens

## Safety boundary

Riley works with Firebase emulators, test users, and Stripe test mode. A mentor owns:

- Production deployment
- Production Firebase and Stripe credentials
- Final approval of Firestore rules
- Pricing-policy changes
- Data migrations
- Any production payment or notification test

No production customer data should be copied into local fixtures.

## Proposed API contract

The final route name may follow the backend's established conventions. One acceptable shape is:

```http
POST /ride-requests
Authorization: Bearer <Firebase ID token>
Idempotency-Key: <unique request key>
Content-Type: application/json
```

### Client request

```json
{
  "pickup": {
    "label": "Pickup address",
    "latitude": 40.000001,
    "longitude": -75.000001
  },
  "dropoff": {
    "label": "Drop-off address",
    "latitude": 40.100001,
    "longitude": -75.100001
  },
  "rideType": "Rydr Go",
  "riderPreferences": {},
  "selectedCandidateId": "opaque-candidate-id",
  "matchSessionId": "match-session-id",
  "quoteFingerprint": "backend-quote-fingerprint",
  "promotionReference": null,
  "replacementForRideId": null
}
```

The caller must not send `riderId`, `driverId`, status, timestamps, expiration, prices, payout, platform share, or notification recipient as trusted values.

### Success response

```json
{
  "rideRequestId": "server-generated-id",
  "status": "pending",
  "selectedCandidateId": "opaque-candidate-id",
  "quote": {
    "pricingVersion": "standard_usd_v2",
    "riderTotalCents": 1100,
    "driverPayoutCents": 720,
    "bookingFeeCents": 300,
    "quoteFingerprint": "backend-quote-fingerprint",
    "expiresAt": "server timestamp"
  },
  "requestExpiresAt": "server timestamp"
}
```

Only return fields required by the Rider app. Do not expose private driver profile, payment, location-history, or matching data.

### Required errors

Use stable machine-readable codes in addition to human-readable messages:

```text
UNAUTHENTICATED
INVALID_ARGUMENT
PAYMENT_METHOD_REQUIRED
MATCH_SESSION_NOT_FOUND
MATCH_SESSION_EXPIRED
CANDIDATE_NOT_IN_SESSION
DRIVER_NO_LONGER_ELIGIBLE
DRIVER_NO_LONGER_AVAILABLE
QUOTE_STALE
PROMOTION_INVALID
REPLACEMENT_RIDE_INVALID
IDEMPOTENCY_CONFLICT
REQUEST_ALREADY_ACTIVE
```

For `QUOTE_STALE`, return the refreshed backend quote when it is safe to do so. The Rider app must show the updated price and require confirmation instead of silently creating the request at a different price.

## Backend processing requirements

The endpoint should perform these steps in order:

1. Verify the Firebase ID token using the existing authentication middleware.
2. Derive `riderId` from that verified token; never accept it from the body.
3. Validate payload shape, coordinates, supported ride type, and idempotency key.
4. Load the canonical rider record and verify account status.
5. Verify a real, usable payment method through a server-owned payment-readiness adapter.
6. Load the match session and verify ownership, purpose, and expiration.
7. Verify that the selected candidate belongs to the session.
8. Revalidate the driver through Deja's matching service.
9. Recalculate the quote using the trusted route result, canonical driver rate card, and `standard_usd_v2`.
10. Compare the recalculated fingerprint to the submitted fingerprint.
11. Validate the promotion or replacement reference without trusting client amounts.
12. In a Firestore transaction, reserve the idempotency key and create the authoritative request and signal.
13. Set server timestamps and server-controlled expiration.
14. Allow the backend-created request event to trigger the existing driver notification.
15. Return the request ID and backend quote.

Do not allow a failure after the request write to leave a conflicting or independently reusable dispatch signal. The request, signal, match-session consumption, and idempotency record should be committed together where Firestore transaction limits permit.

## Canonical document requirements

The backend may preserve the current collection names during migration:

```text
rideRequests/{rideRequestId}
rideRequestSignals/{rideRequestId}
```

At minimum, the backend should own:

```text
rideRequestId
riderId
driverId or internally resolved candidate driver ID
matchSessionId
selectedCandidateId
status
source
rideType
pickup and drop-off
trusted route reference or route snapshot reference
pricingVersion
quoteFingerprint
backend quote breakdown
promotion or replacement references
createdAt
updatedAt
expiresAt
createdBy: backend
```

The dispatch signal should contain only the minimum information needed for backend dispatch/listening. Do not copy private rider, driver, payment, or unnecessary financial data into it.

## Idempotency requirements

- Require a unique idempotency key for every logical create attempt.
- Scope the key to the authenticated rider and operation.
- Store a hash of the normalized request payload.
- A retry with the same key and same payload returns the original request ID.
- The same key with a different payload returns `IDEMPOTENCY_CONFLICT`.
- Parallel retries must create only one request and one signal.
- A consumed match session must not create multiple active requests unless the product contract explicitly allows it.
- Notification retries must not create duplicate user-visible notification records.

## Notification behavior

The existing Firebase trigger watches for a newly created pending request and sends the driver notification. Riley should preserve that backend-triggered flow rather than sending push notifications from the Rider app.

Verify that:

- Only the backend-selected driver receives the notification.
- A duplicate endpoint retry does not create a second request event.
- Trigger retries are deduplicated or overwrite a deterministic notification record.
- Notification failure does not roll back or corrupt the request.
- Notification payloads contain only display-safe data.

## Firestore rules migration

After the Rider app has switched to the endpoint:

- Deny Rider and Driver clients from creating `rideRequests` directly.
- Deny all client creation of `rideRequestSignals`.
- Deny client mutation of match-session, quote, pricing, driver-assignment, expiration, notification, and lifecycle fields.
- Permit the authenticated rider to read their request.
- Permit only the assigned driver to read the pending offer.
- Preserve backend/Admin SDK access.
- Preserve the minimum participant writes still required elsewhere until those flows move behind backend commands.
- Add emulator rule tests before deployment.

Do not merge a broad rules rewrite from an older scheduled-rides branch. Apply narrow changes on top of the current protected rules.

## Rider-app migration

Replace the direct writes in `FirestoreRideService.requestRide` with an authenticated HTTP call.

The Rider app should:

- Send the selected candidate and match-session contract.
- Send an idempotency key that remains stable across network retries.
- Display the backend-returned quote.
- Handle `QUOTE_STALE` by asking the rider to reconfirm.
- Listen to the resulting request document for status changes.
- Never construct authoritative status, expiration, driver assignment, or financial fields.
- Never send a notification directly.

Remove the direct `setData` calls only after endpoint integration tests pass.

## Work plan

### Phase 0 — Trace and contract

- [ ] Run the Rider app and Firebase emulators through one request attempt.
- [ ] Record the current `rideRequests` and `rideRequestSignals` schemas.
- [ ] Trace the existing request notification trigger.
- [ ] Agree on the match-session interface with Deja.
- [ ] Agree on the quote-fingerprint interface with the pricing owner.
- [ ] Document the existing payment-readiness source of truth.
- [ ] Add a sequence diagram to the pull request description.

Checkpoint: Riley, Deja, and a mentor approve the request/matching boundary before implementation.

### Phase 1 — Test scaffolding and endpoint shell

- [ ] Add endpoint tests using mocked or emulated authentication.
- [ ] Add payload validation.
- [ ] Add stable error codes.
- [ ] Add an idempotency repository.
- [ ] Confirm the endpoint derives rider identity from the verified token.

Checkpoint: Authentication, validation, and idempotency tests pass without creating a real request.

### Phase 2 — Matching and quote validation

- [ ] Load the server-owned match session.
- [ ] Verify session ownership and expiration.
- [ ] Verify selected-candidate membership.
- [ ] Call Deja's reusable driver revalidation function.
- [ ] Recalculate the quote with `standard_usd_v2`.
- [ ] Validate the quote fingerprint.
- [ ] Return `QUOTE_STALE` with the refreshed quote where appropriate.

Checkpoint: Tampered candidates, expired sessions, unavailable drivers, and stale quotes are rejected.

### Phase 3 — Atomic request creation

- [ ] Generate the request ID on the backend.
- [ ] Create the request, signal, idempotency record, and match-session consumption atomically.
- [ ] Use server timestamps and backend-controlled expiration.
- [ ] Validate promotion and replacement references.
- [ ] Confirm that only one parallel attempt succeeds.
- [ ] Confirm the existing notification trigger receives the new document shape.

Checkpoint: One logical request produces exactly one authoritative request and signal.

### Phase 4 — Rider integration

- [ ] Add the authenticated endpoint client.
- [ ] Replace direct Firestore request and signal creation.
- [ ] Preserve existing status listeners.
- [ ] Add stale-quote confirmation behavior.
- [ ] Add retry handling using the same idempotency key.
- [ ] Remove unused client payload construction.

Checkpoint: Airplane-mode interruption and retry do not create duplicate requests.

### Phase 5 — Rules hardening

- [ ] Deny direct client creation of authoritative requests.
- [ ] Deny all client creation of request signals.
- [ ] Protect server-owned request fields.
- [ ] Add positive read tests for the rider and assigned driver.
- [ ] Add negative create, cross-user read, and tampering tests.

Checkpoint: A modified client cannot reproduce the backend write directly against Firestore.

### Phase 6 — End-to-end verification

- [ ] Run backend unit and integration tests.
- [ ] Run Firestore emulator rule tests.
- [ ] Demonstrate a successful request and driver notification.
- [ ] Demonstrate unavailable-driver rejection.
- [ ] Demonstrate stale-quote handling.
- [ ] Demonstrate duplicate retry handling.
- [ ] Demonstrate direct Firestore write denial.
- [ ] Document deployment and rollback order.

## Required automated tests

### Authentication and authorization

- [ ] Missing token is rejected.
- [ ] Invalid token is rejected.
- [ ] Body-supplied `riderId` or `driverId` cannot override backend identity or selection.
- [ ] Suspended or disabled rider is rejected.
- [ ] Missing usable payment method is rejected.

### Matching and quote integrity

- [ ] Missing match session is rejected.
- [ ] Expired match session is rejected.
- [ ] Session owned by another rider is rejected.
- [ ] Candidate outside the session is rejected.
- [ ] Offline, busy, suspended, or unqualified driver is rejected.
- [ ] Stale quote fingerprint returns `QUOTE_STALE`.
- [ ] Tampered price fields are rejected or ignored and never persisted as authority.

### Consistency and retries

- [ ] Request and signal are created together.
- [ ] Transaction failure creates neither document.
- [ ] Same idempotency key and payload returns the original result.
- [ ] Same idempotency key with changed payload is rejected.
- [ ] Parallel duplicate requests create one request.
- [ ] Match session cannot be consumed twice unexpectedly.

### Firestore rules

- [ ] Rider cannot directly create a request.
- [ ] Driver cannot directly create a request.
- [ ] No client can create a request signal.
- [ ] Rider can read their request.
- [ ] Assigned driver can read their offer.
- [ ] Unrelated users cannot read the request.
- [ ] Participants cannot change backend-owned fields.

### Notification integration

- [ ] A valid new request triggers the assigned driver's notification.
- [ ] An idempotent retry does not produce a second request notification.
- [ ] No other driver receives the request notification.

## Definition of done

The project is complete only when:

- The Rider app no longer writes `rideRequests` or `rideRequestSignals` directly.
- Every standard request is created through an authenticated backend endpoint.
- Rider identity comes only from the verified Firebase token.
- Payment readiness is verified on the backend.
- The selected candidate is tied to a valid match session created by Deja's service.
- Driver eligibility and availability are revalidated immediately before creation.
- The backend recalculates the `standard_usd_v2` quote and verifies its fingerprint.
- Request creation is idempotent and atomic.
- Status, assignment, timestamps, expiration, and financial quote fields are backend-owned.
- Driver notifications originate from the backend-created event.
- Firestore rules reject equivalent direct client writes.
- Automated tests cover authentication, tampering, stale quotes, concurrency, rules, and notification integration.
- A mentor has reviewed the endpoint, rules diff, tests, and emulator demonstration.

## Pull-request expectations

The pull request should include:

- A short before-and-after data-flow diagram
- The final API request, response, and error contract
- The match-session interface agreed with Deja
- The Firestore schema changes
- Test output
- Emulator demonstration notes
- Deployment order
- Rollback plan
- Any temporary compatibility code and a dated removal issue

Keep unrelated formatting, UI redesigns, pricing changes, and scheduled-ride rewrites out of this pull request.
