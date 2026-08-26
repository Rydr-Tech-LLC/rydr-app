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
- `POST /driver/account-deletion-requests` - authenticated driver account deletion request intake
- `POST /moderation/check-image` - authenticated image moderation for uploaded profile photos
- `POST /rides/:rideId/route-estimate` - authenticated Apple Maps route calculation using the ride's backend-stored pickup, optional stop, and drop-off coordinates. The resulting distance and duration are stored as backend-owned financial inputs.
- `POST /rides/:rideId/transition` - authenticated, participant-authorized backend ride lifecycle command. Supported actions include acceptance, navigation, arrival, paid wait, ride start/stop, completion, and cancellation. Completion/cancellation creates the immutable `rides/{rideId}/financial/outcome` record used by Stripe.

Ride lifecycle requests require a client-generated `requestId` for idempotency. Clients send intent only (`action`, optional cancellation `reason`, and queue intent); authoritative statuses, timestamps, queue promotion, fares, fees, payouts, and payment state are written by the backend. Supported actions are `driver_accept`, `driver_decline`, `driver_miss`, `promote_queue`, `start_navigation`, `arrive_pickup`, `start_paid_wait`, `start_ride`, `arrive_stop`, `leave_stop`, `complete`, `driver_cancel`, and `rider_cancel`.

The rider app requests an Apple Maps route estimate after creating the pending ride request. The backend reuses that trusted estimate during acceptance and finalization, retrying route calculation later if the initial Apple request was unavailable. Apple Maps distance and duration replace legacy client estimates in the immutable financial outcome.

## Environment Variables

```bash
PORT=3000
NODE_ENV=development

FIREBASE_ADMIN_PROJECT_ID=your-firebase-project-id
FIREBASE_ADMIN_CLIENT_EMAIL=firebase-adminsdk@example.iam.gserviceaccount.com
FIREBASE_ADMIN_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n"
FIREBASE_DATABASE_URL=
FIREBASE_STORAGE_BUCKET=rydrapp-c7ec1.firebasestorage.app

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

Integration variables:

- `TICKETMASTER_API_KEY`
- `APPLE_MAPS_TEAM_ID`
- `APPLE_MAPS_KEY_ID`
- `APPLE_MAPS_PRIVATE_KEY` — paste the complete `.p8` contents as a secret; never commit or log it

## Apple Maps Server API

The backend creates a short-lived ES256 developer token with the `server_api` scope, exchanges it for an Apple Maps access token, and caches the access token until shortly before expiration. Route requests use coordinates already stored on the ride; callers cannot submit replacement pickup or drop-off coordinates to the route-estimate endpoint.

The downloaded `.p8` file is ignored by Git. Keep it outside this repository and add its contents only through local environment configuration or Render's secret environment variables.

## Lifecycle Deployment Order

1. Deploy `rydr-backend` with the Apple Maps environment variables.
2. Verify authenticated ride transition and route-estimate calls.
3. Release the rider and driver builds that call the backend lifecycle endpoints.
4. Deploy the updated Firestore rules, which reject direct client lifecycle, queue, financial, and request-signal status changes.

Do not deploy the restrictive Firestore rules before the matching backend and mobile clients are available.

## Future Feature Areas

This backend is structured to support:

- Community
- Discover
- Ticketmaster
- Cash Rydr Hub
- Chat
- Notifications

The event routes call Ticketmaster Discovery. Placeholder/mock Chat, Community Posts, and Notifications routes were removed for TestFlight readiness; add those APIs back only when they are backed by real data and authentication.
