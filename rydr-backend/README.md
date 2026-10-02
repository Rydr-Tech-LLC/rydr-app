# rydr-backend

Primary backend foundation for future Rydr platform features.

This service is intentionally separate from the existing payment and banking services:

- `rydr-stripe-backend` / Stripe backend service
- `rydr-bank-service`

Those services remain operational and should continue to own their current responsibilities. `rydr-backend` is the home for new Rydr platform features including Community, Discover, Ticketmaster, Cash Rydr Hub, Chat, and Notifications.

## Tech Stack

- Node.js
- Express
- Firebase Admin SDK
- Firestore
- dotenv
- cors
- helmet
- morgan

## Folder Structure

```text
src/
├── routes/
│   ├── health.js
│   ├── events.js
│   ├── driver.js
│   └── moderation.js
│
├── services/
│   ├── ticketmasterService.js
│   ├── firestoreService.js
│   ├── driverService.js
│   └── moderationService.js
│
├── middleware/
├── config/
│   └── firebase.js
├── utils/
└── app.js
```

## Local Development

Install dependencies:

```bash
npm install
```

Create a local environment file:

```bash
cp .env.example .env
```

Start the development server:

```bash
npm run dev
```

Start the production server locally:

```bash
npm start
```

## Endpoints

```http
GET /
```

```json
{
  "service": "rydr-backend",
  "status": "online"
}
```

```http
GET /health
```

```json
{
  "status": "healthy"
}
```

Current feature routes:

- `GET /events` - Atlanta event search powered by Ticketmaster Discovery
- `GET /events/:id` - normalized Ticketmaster event detail
- `POST /driver/wait-time-events` - authenticated driver wait-time event logging
- `POST /account/deletion-requests` - authenticated Rider/Driver account deletion request intake; identity and roles are derived from the verified Firebase token
- `POST /driver/account-deletion-requests` - legacy authenticated Driver alias for older app builds
- `POST /account/identity/sync` - reconciles a verified Firebase phone claim with the backend-owned Rider/Driver phone index and canonical account link
- `POST /driver/presence` - authenticated, backend-authorized online/offline presence. The backend verifies driver approval and safety eligibility, derives active-ride availability, and owns private/public status writes.
- `POST /driver/queue/promote-next` - transactionally selects and promotes the driver's oldest eligible queued ride
- `POST /driver/background-check/:action` - records verified Checkr redirect/acknowledgement events without trusting client-supplied screening status
- `PUT /driver/rate-card` - validates and publishes the authenticated driver's private rate card and public rate projection
- `GET /driver/earnings-summary` - derives earnings totals from backend-finalized ride financial outcomes
- `POST /moderation/check-image` - authenticated image moderation for uploaded profile photos
- `POST /moderation/profile-photo/finalize` - moderates a pending photo, promotes approved bytes to permanent Storage, and updates the canonical profile URL server-side
- `POST /rides/:rideId/telemetry` - records authenticated assigned-driver trip evidence and updates the backend-owned live driver location
- `POST /rides/:rideId/rating` - validates completed-ride participation and updates the rated participant's reputation server-side
- `POST /rides/:rideId/route-estimate` - authenticated Apple Maps route calculation using the ride's backend-stored pickup, optional stop, and drop-off coordinates. The resulting distance and duration are stored as backend-owned financial inputs.
- `POST /rides/:rideId/transition` - authenticated, participant-authorized backend ride lifecycle command. Supported actions include acceptance, navigation, arrival, paid wait, ride start/stop, completion, and cancellation. Completion/cancellation creates the immutable `rides/{rideId}/financial/outcome` record used by Stripe.
- `POST /cash-hub/access/accept` and `POST /cash-hub/access/opt-out` - own CashRydr Hub terms acceptance, driver access activation, and monthly obligation creation
- `POST /cash-hub/requests` and Cash Hub command/offer/message routes - own the CashRydr Hub connection state machine and conversations. CashHub uses arrangement formats (`One-way`, `Round trip`, `Scheduled`, or `Flexible`) and the driver's actual vehicle; it does not use Rydr Dispatch service tiers.
- `POST /safety/reports` and `POST /safety/appeals` - derive ride participants and penalty evidence before creating safety records
- `POST /support/tickets`, ticket commands, and `/support/call-requests` - own support intake and ticket transitions

Ride lifecycle requests require a client-generated `requestId` for idempotency. Clients send intent only (`action`, optional cancellation `reason`, and queue intent); authoritative statuses, timestamps, queue promotion, fares, fees, payouts, and payment state are written by the backend. Supported actions are `driver_accept`, `driver_decline`, `driver_miss`, `promote_queue`, `start_navigation`, `arrive_pickup`, `start_paid_wait`, `start_ride`, `arrive_stop`, `leave_stop`, `complete`, `driver_cancel`, and `rider_cancel`.

The rider app requests an Apple Maps route estimate after creating the pending ride request. The backend reuses that trusted estimate during acceptance and finalization, retrying route calculation later if the initial Apple request was unavailable. Apple Maps distance and duration replace legacy client estimates in the immutable financial outcome. If a ride carries a reserved RydrBank code, finalization verifies and consumes it in the same Firestore transaction while preserving the driver's backend-calculated payout.

## Environment Variables

```bash
PORT=3000
NODE_ENV=development

FIREBASE_ADMIN_PROJECT_ID=your-firebase-project-id
FIREBASE_ADMIN_CLIENT_EMAIL=firebase-adminsdk@example.iam.gserviceaccount.com
FIREBASE_ADMIN_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n"
FIREBASE_DATABASE_URL=
FIREBASE_STORAGE_BUCKET=rydrapp-c7ec1.firebasestorage.app
REQUIRE_FIREBASE_APP_CHECK=false

TICKETMASTER_API_KEY=

APPLE_MAPS_TEAM_ID=
APPLE_MAPS_KEY_ID=
APPLE_MAPS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_APPLE_MAPS_P8_KEY\n-----END PRIVATE KEY-----\n"
```

Never commit `.env` or service account secrets.

## Firebase Setup

1. Create or select a Firebase project.
2. Enable Firestore in the Firebase console.
3. Create a Firebase Admin service account key.
4. Copy the service account values into Render environment variables or your local `.env`.
5. Store the private key with escaped newlines, as shown in `.env.example`.

The Firebase Admin SDK is configured in `src/config/firebase.js`. Firestore access is prepared through `src/services/firestoreService.js`.

## Render Deployment

This project includes `render.yaml` for Render Blueprint deployment.

Render settings:

- Runtime: Node
- Build command: `npm install`
- Start command: `npm start`
- Health check path: `/health`

Required Render environment variables:

- `NODE_ENV=production`
- `FIREBASE_ADMIN_PROJECT_ID`
- `FIREBASE_ADMIN_CLIENT_EMAIL`
- `FIREBASE_ADMIN_PRIVATE_KEY`
- `FIREBASE_DATABASE_URL`, if needed by your Firebase project
- `FIREBASE_STORAGE_BUCKET=rydrapp-c7ec1.firebasestorage.app`, required for profile photo moderation
- `REQUIRE_FIREBASE_APP_CHECK=true`, required in production for authenticated CashRydr Hub mutations

Integration variables:

- `TICKETMASTER_API_KEY`
- `APPLE_MAPS_TEAM_ID`
- `APPLE_MAPS_KEY_ID`
- `APPLE_MAPS_PRIVATE_KEY` — paste the complete `.p8` contents as a secret; never commit or log it

## Apple Maps Server API

The backend creates a short-lived ES256 developer token with the `server_api` scope, exchanges it for an Apple Maps access token, and caches the access token until shortly before expiration. Route requests use coordinates already stored on the ride; callers cannot submit replacement pickup or drop-off coordinates to the route-estimate endpoint.

The downloaded `.p8` file is ignored by Git. Keep it outside this repository and add its contents only through local environment configuration or Render's secret environment variables.

## Backend-Ownership Deployment Order

1. Deploy `stripe-backend` first with `RYDR_INTERNAL_SERVICE_TOKEN`, `RYDR_INTERNAL_ADMIN_SECRET`, and `/health` configured as its Render health check. Use the service token's same high-entropy value for the Firebase Functions secret of that name; use the admin secret's same value only in Mission Control.
2. Set the Firebase secret with `firebase functions:secrets:set RYDR_INTERNAL_SERVICE_TOKEN`. Set `RYDR_STRIPE_BACKEND_URL` if the Stripe service is not at the default Render URL, then deploy Firebase Functions. The payment worker must exist before the main backend can create payment jobs.
3. Deploy `rydr-bank-service`, configure `/health`, `CORS_ORIGINS`, and `RYDR_WEB_BOOKING_SECRET`, and verify its authoritative completed-ride checks.
4. Deploy `rydr-backend` with the Apple Maps environment variables and `REQUIRE_FIREBASE_APP_CHECK=true`. Use a non-sleeping instance for dispatch and lifecycle traffic.
5. Verify authenticated identity sync, profile-photo finalization, screening, rate-card, telemetry, rating, Cash Hub, safety, support, queue-promotion, ride-transition, earnings-summary, route-estimate, payment-job, and Rydr Bank calls.
6. Release the Rider and Driver builds that call the new backend-owned endpoints.
7. Deploy the updated Firestore and Storage rules, which reject direct client writes to authoritative lifecycle, queue, telemetry, ratings/reputation, screening, rate-card projection, Cash Hub, chat metadata, safety/support intake, permanent profile photos, phone indexes/account links, vehicle eligibility, financial, driver-presence, and request-signal state.
8. Enforce Firebase API App Check only after every active app that accesses those APIs is registered. Custom-backend App Check is independently enforced by `rydr-backend`.

Do not deploy the restrictive Firestore or Storage rules before the matching backend and mobile clients are available. Existing TestFlight builds still use some of the direct writes that the new rules intentionally reject.

## Future Feature Areas

This backend is structured to support:

- Community
- Discover
- Ticketmaster
- Cash Rydr Hub
- Chat
- Notifications

The event routes call Ticketmaster Discovery. Placeholder/mock Chat, Community Posts, and Notifications routes were removed for TestFlight readiness; add those APIs back only when they are backed by real data and authentication.
