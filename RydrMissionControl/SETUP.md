# Rydr Mission Control — Setup & Deployment

Internal staff portal for driver verification, rider/driver lookup, safety
reports, and beta-tester tracking. Next.js (App Router) + TypeScript +
Tailwind, reading/writing the same Firestore project as RydrDriver and
RydrPlayground.

## 1. How authorization actually works

There is no trusted role field stored anywhere a browser can edit. Access is
gated by a Firebase Auth **custom claim**, which only a server with your
Firebase Admin service account can set:

- `role: "admin"` grants full Mission Control access.
- `role: "marketing"` grants access only to Campus Growth, its modules, and
  personal Settings for changing the user's own password.

1. Staff member signs in with email/password (Firebase Auth) on `/login`.
2. The client sends the resulting ID token to `POST /api/session`.
3. That route verifies the token, approved role, and `@rydr-go.com` email
   domain before issuing an httpOnly session cookie.
4. Portal pages and every privileged API route
   (`/api/drivers/[uid]/decision`, `/api/riders/[uid]/status`,
   `/api/reports/[id]/action`) re-verify that cookie server-side. Admin-only
   routes call `getAdminSession()`. Campus Growth routes call
   `getCampusGrowthSession()`, which accepts Admin or Marketing. The browser
   is never trusted, including when someone enters a URL directly.
5. All backend-owned Firestore fields (`driverApprovalStatus`, `approvedAt`,
   `approvedBy`, `isApproved`, etc.) are written only by the Admin SDK
   (`lib/firebaseAdmin.ts`), which bypasses Firestore security rules
   entirely — consistent with how those fields are already blocked from
   client writes in `Rydr_Firebase/firestore.rules` via
   `backendOwnedProfileFields()`.

No staff member has Mission Control access until you explicitly grant it
(step 4 below).

## 2. Environment variables

Copy `.env.example` to `.env.local` and fill in:

- `NEXT_PUBLIC_FIREBASE_*` — from Firebase Console → Project settings →
  General → Your apps → (add a Web app if one doesn't exist yet; this is
  separate from the iOS apps' bundle IDs, just a config object, no App Store
  identifier involved).
- `FIREBASE_ADMIN_*` — from Firebase Console → Project settings → Service
  accounts → Generate new private key. This downloads a JSON file; copy
  `project_id`, `client_email`, and `private_key` into the matching env vars.
  Paste the private key as a single line with literal `\n` for newlines
  (most password managers / Vercel's env UI handle multi-line values fine
  too — just don't strip the `-----BEGIN PRIVATE KEY-----` header).

**Never commit `.env.local`.** It's already in `.gitignore`.

## 3. Granting/revoking staff access

Use **Settings → Mission Control Users** to create a `@rydr-go.com` login or
grant an existing Firebase Auth user either Admin or Marketing access. This
is the preferred workflow because it records the selected role and audit
information. A newly created user receives the temporary password entered by
the admin, then can replace it under their own Settings after signing in.

The legacy command below grants full Admin access only:

```bash
npm install
npm run set-admin -- someone@rydr-go.com          # grant
npm run set-admin -- someone@rydr-go.com --revoke  # revoke
```

The user must have an existing Firebase Auth account first (create one in
Firebase Console → Authentication → Add user, or have them sign up once via
any flow that hits the same Firebase project). They need to sign out and
back in after the claim changes — custom claims are baked into the ID token
at sign-in time.

## 4. Run locally

```bash
npm install
npm run dev
```

Visit `http://localhost:3000`, then sign in with an approved Admin or
Marketing account.

## 5. Deploy to Vercel under rydr-go.com

1. Push this `RydrMissionControl` folder as its own Vercel project (it's
   independent of `Rydr_Website` — separate Next.js app, separate deploy).
2. In Vercel → Project → Settings → Environment Variables, add every
   variable from `.env.example` (use the real values, not the placeholders).
3. Pick a subdomain so it stays clearly separate from the public site —
   e.g. `mc.rydr-go.com` or `ops.rydr-go.com`. Add that domain in Vercel →
   Project → Settings → Domains, then add the CNAME Vercel gives you in
   wherever `rydr-go.com`'s DNS is managed.
4. Deploy. First sign-in attempt will fail for everyone until you've run
   `npm run set-admin` for at least one account (step 3 above) — do that
   against the **same Firebase project** these env vars point to.

## 6. What's real vs. stubbed right now

This portal is built against the actual Firestore schema your apps already
write (see `lib/types.ts` for field-by-field mapping back to
`DriverSignupCoordinator.swift` / `DriverDashboardVM.swift`). A few things
will look empty or incomplete until other parts of the platform catch up —
this is expected, not a bug in Mission Control:

- **License/insurance/registration images** read both the current Firebase
  document review schema (`documents.<kind>.downloadURL` / `frontURL` /
  `backURL` / `documentURL`) and the legacy review aliases
  (`license.imageUrl`, `vehicle.insuranceImageUrl`,
  `vehicle.registrationImageUrl`). New uploads also denormalize those legacy
  aliases for compatibility.
- **Stripe Identity / Stripe Connect status** read both the Stripe webhook
  fields (`identityStatus`, `identityVerified`, `stripeAccountId`,
  `stripeChargesEnabled`, `stripePayoutsEnabled`) and the Mission Control
  aliases (`stripeIdentityStatus`, `stripeConnectStatus`). New Stripe events
  write the aliases too.
- **Background check** intentionally shows "Beta Deferred" as a satisfying
  state — no real Checkr integration exists yet, and isn't expected to for
  the beta. `backgroundCheckStatus: "beta_deferred"` plus
  `betaAgreementAccepted: true` is enough to unblock approval.
- **Safety Reports** lists rider incident reports written by the iOS rider app
  to `safetyReports`. Deploy `Rydr_Firebase/firestore.rules` with
  `firebase deploy --only firestore:rules` before relying on this in beta.
- **Driver/Rider Search** does a bounded in-memory scan (good for beta-scale
  data, a few hundred to low thousands of users). Swap for a real search
  index later if either collection grows large.

## 7. Adding future modules

Each module listed in the spec (Checkr Review Queue, Stripe Connect
Monitoring, Ride Disputes, Refund Requests, Driver Appeals, Analytics, Promo
Codes, Marketing, Community Moderation, Customer Support) should be added as
its own route under `app/(portal)/<module>/page.tsx`, with a new entry in
`NAV_ITEMS` in `components/Sidebar.tsx`. Any privileged write it needs should
go through a new `app/api/<module>/.../route.ts` route that calls
`getAdminSession()` first and `writeAuditLog()` after, matching the pattern
in `app/api/drivers/[uid]/decision/route.ts` — that's the whole contract this
architecture is built around.
