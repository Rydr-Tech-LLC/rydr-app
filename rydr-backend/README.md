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
│   ├── community.js
│   ├── chat.js
│   └── notifications.js
│
├── services/
│   ├── ticketmasterService.js
│   ├── firestoreService.js
│   └── notificationService.js
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
- `GET /community/posts`
- `POST /community/posts`
- `GET /chat/conversations`
- `POST /chat/message`
- `GET /notifications`

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

## Future Feature Areas

This backend is structured to support:

- Community
- Discover
- Ticketmaster
- Cash Rydr Hub
- Chat
- Notifications

The event routes call Ticketmaster Discovery. The remaining placeholder routes preserve service boundaries for future implementation.
