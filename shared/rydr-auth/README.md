# @rydr/auth-core

Shared Firebase authentication and authorization helpers for Rydr's Node backends: `rydr-backend`, `stripe-backend` and `rydr-bank-service`.

The package answers two questions about a request: **who is calling** (a valid Firebase ID token) and **what role they have** (driver, admin). Each service still decides what that caller may do with its own data. Ride, payment and promo-code ownership checks are not part of this package.

The package was also created to create a consistent authentication layer across the the three backends mentioned above. Each of these backends repeated the same authentication logic, requiring a lot more manual work to have the 3 services consistent. This shared package allows the authentication to be in once location, making it easier to maintain and have any changes to the authentication be applied to the three services equally.

Design goal: small enough to read in one sitting. Plain JavaScript, no runtime dependencies, no build step.

> **Status:** package code is written; tests are not yet. No service installs it yet — that waits on confirming how the package reaches each Render build (see the [proposal](document/AUTH_LAYER_AUDIT_AND_PROPOSAL.md), Part 3, "Gate").

## Install

Add it to the service's `package.json`:

```json
"dependencies": {
  "@rydr/auth-core": "file:../shared/rydr-auth"
}
```

This path is the starting point and is still being confirmed against Render. If a service's Render build can't see `shared/`, the dependency may become a vendored copy (`file:./vendor/rydr-auth`), a private npm package, or a Git dependency.

Requires Node 18+.

## Quick start

Each service initializes Firebase Admin exactly as it does today, then passes its initialized `admin` instance to the package once:

```js
// CommonJS (rydr-backend, stripe-backend)
const { createAuth } = require("@rydr/auth-core");
```

```js
// ESM (rydr-bank-service) — either form works
import { createAuth } from "@rydr/auth-core";
import rydrAuthCore from "@rydr/auth-core"; // then rydrAuthCore.createAuth
```

```js
const auth = createAuth({ admin }); // admin = the service's own firebase-admin

router.use(auth.requireAuth);                       // 401 unless a valid Firebase Bearer token
router.post("/x", auth.requireDriver, handler);     // 403 unless drivers/{uid} exists
router.post("/admin/y", auth.requireAdmin({ allowInternalSecret: true }), handler);

// inside a handler:
if (!auth.assertOwnsUid(req, res, req.body.uid)) return;
```

The package never imports `firebase-admin` itself and never touches credentials. Passing `admin` in also lets tests use a small fake instead of a real Firebase project.

## API

`createAuth({ admin })` is the package's only export. It returns:

### `requireAuth(req, res, next)`

Express middleware.

1. Reads `Authorization: Bearer <token>`. Missing or malformed → `401`, logs `token_missing`.
2. Verifies the token with `admin.auth().verifyIdToken()`. Throws (invalid, expired) → `401`, logs `token_invalid` with the Firebase error code only.
3. On success sets `req.user = { uid, claims }`, where `claims` is the decoded token.

Also sets `req.firebaseUid` and `req.uid` as aliases so existing route code keeps working during migration. New code should use `req.user.uid`; the aliases will be removed once every service is migrated.

### `requireDriver(req, res, next)`

Express middleware. Must run **after** `requireAuth`.

- No `req.user` (used without `requireAuth`) → `401 "Authentication required before role check"`.
- `drivers/{req.user.uid}` exists in Firestore → `next()`.
- Document missing → `403 "driver account required"`, logs `role_denied`.
- Firestore lookup throws → fails closed with the same `403`, logs `role_check_error`.

A driver is "has a `drivers/{uid}` document," which is how `stripe-backend` already decides. No custom claim is required.

### `requireAdmin({ allowInternalSecret = false } = {})`

A factory: call it to get the middleware (`auth.requireAdmin({ ... })`, not `auth.requireAdmin`). It does **not** need `requireAuth` in front of it — it reads and verifies the Bearer token itself, because `stripe-backend`'s admin route has no auth middleware in front of it.

1. If `allowInternalSecret` is true and the `x-internal-admin-secret` header equals `process.env.RYDR_INTERNAL_ADMIN_SECRET` (both must be set), the caller is treated as admin. Used for Mission Control's server-to-server calls. Sets `req.user = { uid: <x-admin-uid header or "mission-control">, claims: { admin: true, via: "internal-secret" } }`.
2. Otherwise reads the Bearer token. Missing or malformed → `401`.
3. Verifies it. Throws → `401`, logs `token_invalid`.
4. Admin claim (`admin === true` or `role === "admin"`) → sets `req.user = { uid, claims }`, `next()`. Not admin → `403 "admin_required"`, logs `role_denied`.

Same decision logic as `stripe-backend`'s `requireAdminUid`. The only difference is the response body, which uses the standard shape below (`{ error: "forbidden", message: "admin_required" }` instead of `{ error: "admin_required" }`). No client reads `"admin_required"`.

### `assertOwnsUid(req, res, candidateUid)`

A plain function, not middleware. Call it inside a handler and stop if it returns `false`:

```js
if (!auth.assertOwnsUid(req, res, req.body.uid)) return;
```

- `candidateUid === req.user.uid` → returns `true`.
- Otherwise (including no `req.user`) → sends `403 "uid does not match the authenticated user"`, logs `ownership_mismatch`, returns `false`.

Pure uid comparison: no Firestore access, no knowledge of rides, payments or promo codes.

## Error responses

Every failure uses one of two shapes:

```
401 { "error": "unauthorized", "message": "<detail>" }   // caller's identity couldn't be established
403 { "error": "forbidden",    "message": "<detail>" }   // authenticated, but not allowed
```

The apps only check for `"unauthorized"` (`RiderIdentityVerificationService.swift`), which `stripe-backend` already returns, so this shape doesn't break clients.

## Security logging

All logging goes through `logAuthEvent`, which accepts only these fields: `event`, `uid`, `route`, `reason`, `code`. It never takes a request, token or error object, so a bearer token, a decoded ID token (which contains email/phone) or a request body can't end up in logs by accident. Entries are written with `console.error` under a `[rydr-auth]` prefix.

Only failures and denials are logged, never successful requests:

| Event | When |
|---|---|
| `token_missing` | `requireAuth` got no `Authorization` header, or a malformed one |
| `token_invalid` | `verifyIdToken` threw (`requireAuth`, or `requireAdmin`'s own token check) |
| `role_denied` | `requireDriver` found no `drivers/{uid}` document, or `requireAdmin` found no admin claim |
| `role_check_error` | `requireDriver`'s Firestore lookup threw |
| `ownership_mismatch` | `assertOwnsUid` uid mismatch |

## What this package does not do

- **Ride-specific ownership and state checks.** "Does this caller own this ride, and is the ride in a state that earns a reward?" is domain logic and stays in the service that owns it: `stripe-backend` keeps `ownedRide()` and its payment helpers, and `rydr-bank-service` keeps its promo-code checks and the `/rides/complete` checks. If a second service ends up copy-pasting the same ownership lookup, that's the time to consider a generic helper, with that service's owner.
- **Firebase Admin initialization and credentials.** Each service keeps its own. `stripe-backend` initializes lazily (`initializeFirebase()`), so it must initialize before calling `createAuth({ admin })` or before the admin route runs.
- **Stripe webhook signature verification.** A different mechanism (Stripe is the caller).
- **Public routes.** Health checks, event listings, Stripe return pages and the marketing-site promo routes stay unauthenticated; the package is only applied where a service wraps a route with it.

## CommonJS and ESM

The package is plain CommonJS, which covers both module systems: CommonJS services `require()` it directly, and ESM services (`rydr-bank-service`) import it through Node's ESM-to-CommonJS interop. Both the named and default import shown in Quick start are verified on Node 20.17.

Keep `index.js` ending in `module.exports = { createAuth }`. That plain object-literal form is what lets Node detect `createAuth` as a named export for ESM callers.

## Layout

```
shared/rydr-auth/
  package.json            # name "@rydr/auth-core", no dependencies
  index.js                # createAuth() — composes the pieces below, implements nothing
  src/
    verifyToken.js        # requireAuth
    roles.js              # requireDriver, requireAdmin
    ownership.js          # assertOwnsUid
    responses.js          # unauthorized() / forbidden() — the 401/403 shape
    logger.js             # logAuthEvent — fixed-field logging
  tests/
    *.test.js             # one file per module; run with `npm test` (`node --test`)
  document/
    AUTH_LAYER_AUDIT_AND_PROPOSAL.md   # audit, /rides/complete finding, rollout plan
    Architecture Decision Records.md   # why the package is built the way it is
```

`responses.js` and `logger.js` are internal; services go through `createAuth`. Export them later only if a service actually needs them.

## Testing

Tests use only what ships with Node 18+ (`node:test`, `node:assert`), with a fake `admin` — no test framework to install. Run them with `npm test` from `shared/rydr-auth/`.

All mock data lives in `tests/helpers.js`: fake users and tokens (`MOCK_TOKENS`), which uids have a driver document (`MOCK_DRIVER_UIDS`), a fake `admin` (`createMockAdmin`), fake Express `req`/`res` objects, and `captureLogs` for checking what gets logged. Nothing talks to a real Firebase project. Name each test file `*.test.js` (or `*.test.mjs` for ESM) so `node --test` finds it; `helpers.js` has no `.test` suffix, so it isn't run on its own. The planned cases are listed in the proposal, Part 3, "Automated authentication tests."

## Future upgrades

Not in the current scope — the package keeps today's behavior exactly. Listed so they aren't lost.

- **Constant-time comparison for the internal admin secret.** `requireAdmin` compares `x-internal-admin-secret` to `RYDR_INTERNAL_ADMIN_SECRET` with a plain `===`, matching `stripe-backend` today. A plain `===` can return early on the first mismatched character, which in theory leaks timing information about how much of a guess was right. The fix is Node's built-in `crypto.timingSafeEqual` (no new dependency). It throws if the two buffers differ in length, so check lengths first:

  ```js
  const crypto = require("crypto");

  function secretsMatch(a, b) {
    const bufA = Buffer.from(a);
    const bufB = Buffer.from(b);
    if (bufA.length !== bufB.length) return false;
    return crypto.timingSafeEqual(bufA, bufB);
  }
  ```

  Best done as its own small PR after the migration, so it's the only behavior change in that diff.
