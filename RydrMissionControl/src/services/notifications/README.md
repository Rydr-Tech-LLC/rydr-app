# Rydr Transactional Notifications

Server-only transactional notification layer for Mission Control and backend API routes.

## Architecture

```text
src/services/notifications/
  EmailService.ts
  NotificationService.ts
  templates/
    genericTemplate.ts
    waitlistConfirmation.ts
    betaApproved.ts
```

- `EmailService` owns the Resend SDK instance and is the only place that sends email through Resend.
- `NotificationService` owns high-level product events such as waitlist confirmation and beta approval.
- `templates/*` contain HTML and plain-text email generation only.

All files that touch Resend import `server-only`, so the Resend API key is never bundled into client code.

## Environment Variables

Required:

```bash
RESEND_API_KEY=
WAITLIST_FROM_EMAIL="Rydr Beta <beta@rydr-go.com>"
```

Optional:

```bash
TESTFLIGHT_RIDER_URL=
TESTFLIGHT_DRIVER_URL=
DISCORD_INVITE_URL=
```

Optional values may be omitted. Missing TestFlight or Discord URLs simply hide those buttons in the beta approval email.

## Sending A Notification

Use `NotificationService` from a server-only context such as a Next.js route handler, server action, or backend service.

```ts
import { notificationService } from "@/src/services/notifications/NotificationService";

const result = await notificationService.sendWaitlistConfirmation({
  to: "driver@example.com",
  firstName: "Jordan"
});

if (!result.ok) {
  // Log or persist the failure, but do not roll back the database write.
  console.error(result.error);
}
```

Email failures are returned as `{ ok: false, error }` and logged by `EmailService`. They do not throw by default and should not block Firestore writes.

## Adding A Template

1. Add a new file under `templates/`, for example `driverDocumentsRequired.ts`.
2. Return an `EmailTemplateOutput` with `subject`, `html`, and `text`.
3. Use `genericTemplate()` for the wrapper and inline styles.
4. Add a high-level method to `NotificationService`, for example `sendDriverDocumentsRequired()`.
5. Call `EmailService.sendEmail()` only from `NotificationService`; do not instantiate Resend in route handlers.

This keeps future templates isolated, including:

- Driver Approved
- Driver Documents Required
- Driver Suspended
- Ride Receipt
- Password Reset
- Email Verification
- RydrBank Reward
- CashRydr Hub
- Referral Reward

## Operational Notes

- Resend API keys must remain server-side.
- Do not use `NEXT_PUBLIC_` for any email provider secret.
- Log messages intentionally exclude API keys and full provider payloads.
- If Resend is unavailable, database writes should still complete and the failure should be visible in server logs.
