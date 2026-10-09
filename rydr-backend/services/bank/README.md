# Rydr Bank Service

Rydr Bank treats Firestore as the authoritative source for completed rides.
`POST /rides/complete` and authenticated promo consumption ignore client fare,
distance, and ride-type values. They verify the caller owns a completed ride
with a backend-finalized financial outcome before applying reward logic.

The non-user web booking routes require an `X-Rydr-Booking-Token`. A trusted
booking backend must create a short-lived HMAC-SHA256 token using
`RYDR_WEB_BOOKING_SECRET`; browser code must never receive that secret. The
token binds the action, code, normalized email, booking/ride ID, ride type,
distance, and an expiry no more than 15 minutes in the future.

## Render configuration

- Root directory: `rydr-backend/services/bank`
- Build command: `npm ci`
- Start command: `npm start`
- Health check path: `/health`
- Configure the variables shown in `.env.example` and mount the Firebase
  service-account JSON as `/etc/secrets/firebase.json`.
- Use a non-sleeping instance before this service is placed in a time-sensitive
  production booking or reward path.

Run `npm test` before deployment.
