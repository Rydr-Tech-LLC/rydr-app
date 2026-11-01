# Rydr Backend Authentication Layer — Audit & Proposal

**Scope:** Document current authentication/authorization behavior across the three Node backends (`rydr-backend`, `stripe-backend`, `rydr-bank-service`), propose a shared auth module structure, and document the `rydr-bank-service` `/rides/complete` finding and its correction.
**Date:** September 16, 2026 (revised September 18, 2026 after re-verifying every claim against the live code; revised October 5, 2026 after tech lead clarified the package name and the shared-folder path; revised October 19, 2026 after tech lead clarified the required shape of the `/rides/complete` fix; revised October 26, 2026 to match the `shared/rydr-auth` code as written)
**Status:** The `shared/rydr-auth` package code is written (`index.js` + `src/`), but tests are not written yet and no service installs or imports it. No service code has changed — that waits on the Render gate in Part 3.

### Decisions and revision history

The architecture decisions from each revision of this proposal now live in [Architecture Decision Records.md](Architecture%20Decision%20Records.md) (ADR-001 to ADR-015), with their status and date. Corrections that weren't decisions:

- **September 18:** corrected the distance field name — the ride document stores `estimatedDistanceMiles`, not `estimate.distanceMiles`; added two repo-hygiene notes (1d); removed a sentence claiming the approach was "agreed with the supervisor," which nothing on record supports.
- **October 19:** moved the `paymentStatus`-is-forgeable finding to the Appendix as a separate item for the tech lead; tightened the "Known limitation" paragraph so it doesn't imply the payment check fixes distance provenance.
- **October 26:** brought the doc in line with the `shared/rydr-auth` code as written, then moved the package description and API to [README.md](../README.md) and the decisions to the ADR file.

## Executive Summary

Each of the three backends implements Firebase ID token verification independently, with no shared code. Two of the three (`rydr-backend`, `stripe-backend`) have already grown reasonably solid per-route ownership checks over time (see prior `PHASE_4_DELIVERABLE.md` and the "Payment Hardening" comments in `stripe-backend/index.js`), but the logic is copy-pasted and drifting: three different 401 shapes, no shared role/admin model, no shared logging discipline, and zero automated tests for any of it. `rydr-bank-service` is the least hardened of the three — its `/rides/complete` route authenticates the caller but then accrues RydrBank rewards from ride data the client sent in the request body, with no check that the ride exists, is complete, or belongs to that caller. That is the finding this proposal treats as the priority fix.

The plan: extract the parts that are already duplicated into one small internal package, add the one check that doesn't exist anywhere yet (role/admin authorization) plus a generic uid-match helper, leave ride-specific ownership checks in the service that owns the ride logic, standardize on one 401/403 shape and one safe logging pattern, and add the automated tests that currently don't exist for any of this. `rydr-bank-service`'s `/rides/complete` gets rewritten to look up the ride server-side instead of trusting the body, as its own change once the shared package exists; the ride checks themselves live inside `rydr-bank-service`, not in the shared package. **One caveat the first draft missed:** that lookup is only as trustworthy as who is allowed to write ride documents, and today's Firestore rules let a rider write their own (Part 2, "Why the lookup alone is not enough"). The bank-service fix and a small Firestore-rules tightening need to ship together for the fix to actually close the hole.

---

## Part 1 — Current Behavior, Per Service

### 1a. `rydr-backend` (`src/middleware/firebaseAuth.js`)

Already has the shape we want to generalize:

- `requireFirebaseAuth` — reads `Authorization: Bearer <token>`, calls `admin.auth().verifyIdToken()`, sets `req.firebaseUid` / `req.firebaseToken`, or `401 { error: "Firebase ID token is required" }` / `401 { error: "Invalid Firebase ID token" }`.
- `assertOwnsUid(req, res, candidateUid)` — a reusable-but-local ownership helper: rejects with `403 { error: "uid does not match the authenticated user" }` unless a body-supplied uid matches `req.firebaseUid`.
- Applied via `router.use(requireFirebaseAuth)` in [driver.js](rydr-backend/src/routes/driver.js) and [moderation.js](rydr-backend/src/routes/moderation.js); every route in those two files then does its own ownership check (`assertOwnsUid` in driver.js; a regex ownership check against `req.firebaseUid` in moderation.js for storage paths).
- **No role or admin concept exists in this service at all.** There are no driver-only or admin-only routes here — everything gated is rider/driver-self-service.
- Public by design and correctly unauthenticated: [health.js](rydr-backend/src/routes/health.js) (`GET /`, `GET /health`) and [events.js](rydr-backend/src/routes/events.js) (Ticketmaster listing proxy — no user data, nothing to authenticate).
- Logging: `console.error("Firebase ID token verification failed", { code, message })` on failure — already reasonably safe (logs the Firebase error code/message, never the token itself). No successful-auth logging exists.

### 1b. `stripe-backend` (`index.js`)

No middleware file — auth is a handful of local async functions called at the top of each handler:

- `verifiedFirebaseUid(req)` / `requireFirebaseUid(req, res)` — same Bearer-token-then-`verifyIdToken` pattern, but returns `401 { error: "unauthorized" }` on any failure, and additionally `500 { error: "firebase_admin_misconfigured" }` if the failure looks like a credential-setup problem rather than a bad token (`isFirebaseAdminConfigError`).
- `requireAdminUid(req, res)` — the only admin-authorization code in the whole codebase. Two paths: (1) a shared-secret server-to-server header (`x-internal-admin-secret` + `x-admin-uid`) for Mission Control, whose own auth is a session cookie and therefore can't present a Firebase Bearer token; (2) a normal Firebase ID token whose decoded claims have `admin === true` or `role === "admin"`, else `403 { error: "admin_required" }`. Used only by `POST /admin/cleanup-account`.
- Ownership, not just authentication, is enforced per-route via a small set of helpers: `ownedRide(uid, rideId)` (loads a ride and returns `null` if `data.riderId !== uid`, so callers can respond 404 without leaking whether the ride exists or just isn't theirs), `ownedCustomerId(uid)`, `rejectIfSuppliedUidMismatch`, `rejectIfSuppliedCustomerMismatch`, `rejectIfSuppliedAccountMismatch`. The comment block above them (index.js:353-359) states the rule explicitly: client-supplied `customerId`/`paymentMethodId`/`driverAccountId` are only ever used to *detect and reject a mismatch*, never to authorize an action — everything is re-derived server-side from the verified uid.
- Public by design and correctly unauthenticated: `GET /` (health), `GET /config` (publishable key only — safe to expose), `POST /webhook` (auth is the Stripe signature, `stripe.webhooks.constructEvent`, checked before the JSON body parser even runs — this is intentional and must stay unauthenticated by Firebase, since Stripe itself is the caller).
- Logging: `console.warn("⚠️ Firebase auth failed", err.message)`, `console.error` with the error object on route failures. Emoji-prefixed, human-readable, but not structured — fine for now; the shared package's logging is described in [README.md](../README.md#security-logging).

### 1c. `rydr-bank-service` (`server.js`)

The thinnest of the three:

- `requireAuth` (server.js:30-41) — same Bearer/`verifyIdToken` pattern, sets `req.uid`, `401 { error: "Missing token" }` / `401 { error: "Invalid token" }`.
- Applied to every user-facing route except two intentionally public ones (`/web/promo/preview`, `/web/promo/consume` — see below).
- **Ownership checks exist for the promo-code routes** (`/promo/preview`, `/promo/release`, `/promo/consume`, `/promo/transfer`) — each loads the code from Firestore and checks `idxSnap.get("currentOwnerUid") !== req.uid` before acting. This part is fine.
- **`/rides/complete` (server.js:273-285) has no ownership or existence check at all.** This is the finding — detailed in Part 2.
- No role or admin concept exists in this service either.
- Public by design and correctly unauthenticated: `GET /` (health), `POST /web/promo/preview` and `POST /web/promo/consume` (server.js:538, 577) — these exist specifically so a *non-Rydr-user* gift recipient can redeem a promo code from the marketing site without an account; ownership there is proven by knowing the code + the email it was sent to (`currentOwnerUid === "external:" + email`), not by Firebase auth. This is a deliberate design, not a gap — must be preserved as-is.
- Logging: `console.error(e)` on every catch block — logs the raw error object, which for these routes is always a `new Error("some_reason")` with no user-supplied data attached, so this is safe today. Flagged here only so it doesn't silently regress if someone later attaches request data to a thrown error.

### 1d. Out of scope, noted for completeness

`RydrMissionControl` (admin web app) authenticates admins via a session **cookie**, not a Firebase Bearer token (`lib/session.ts`, `lib/missionControlAccess.ts`), and has its own two-role model (`"admin" | "marketing"`, `lib/missionControlAccess.ts:4`). It's a Next.js server, not one of the three Express services this proposal touches, and it already has a working, different auth mechanism — the shared package below is **not** meant to replace it. The only place the two worlds meet is `stripe-backend`'s shared-secret admin path (1b above), which stays as-is.

Two repo notes that affect the rollout, neither changed by this proposal:

- `RydrDriver/stripe-backend/index.js` is a 12-line stub that deliberately `throw`s ("decommissioned — deploy the hardened root stripe-backend"). It is not a fourth service and needs no migration. Leave it.
- `stripe-backend/node_modules/` is **committed to git** (1,225 tracked files) even though the root `.gitignore` excludes `node_modules/`. Adding a `file:` dependency to that service will write into a tracked `node_modules`. Recommend a separate cleanup commit (`git rm -r --cached stripe-backend/node_modules`) before that migration step.

---

## Part 2 — Finding: `rydr-bank-service` `POST /rides/complete`

**File:** [rydr-bank-service/server.js:273-285](rydr-bank-service/server.js#L273-L285)

```js
app.post("/rides/complete", requireAuth, async (req, res) => {
  try {
    const { rideId, distanceMi, rideType } = req.body || {};
    if (!rideId || typeof distanceMi !== "number") {
      return res.status(400).json({ error: "rideId and distanceMi required" });
    }
    const out = await accrueAndMaybeMintInOneTxn(req.uid, rideId, distanceMi, rideType);
    return res.json(out);
  } catch (e) { ... }
});
```

`requireAuth` proves the caller has a valid Firebase session — it does **not** prove anything about `rideId`, `distanceMi`, or `rideType`, all three of which come straight from the request body and are trusted as-is. `accrueAndMaybeMintInOneTxn` uses `distanceMi >= 5` as the reward-eligibility gate and `rideType` to pick which reward bucket (`go_eco` / `xl` / `prestine` / `executive`) gets credited, and mints a transferable promo code every 10th eligible ride.

Confirmed on the client side that this is exactly what's sent: `Features/Booking/RideManager.swift:982,1002` — `let distance = ride.estimate.distanceMiles` (the *app's own routing estimate*, not a driver-confirmed or server-measured distance) is passed straight through to `RydrBankAPI.rideComplete(rideId:distanceMi:rideType:)`.

**Impact.** Any authenticated user (a real rider account is enough — no special privilege needed) can call this endpoint directly with a fabricated `rideId` and `distanceMi: 999`, `rideType: "executive"`, repeatedly, to mint an unlimited number of free-ride promo codes, without ever taking a ride. The only existing guard against *repeating the same rideId* is `contribRef` (`users/{uid}/rydrContrib/{rideId}`) — a per-user idempotency doc keyed on whatever `rideId` string the client chooses — which does nothing to stop a script from incrementing `rideId` on every call (`"fake-1"`, `"fake-2"`, ...). There is no check that:
1. a ride with this `rideId` exists in Firestore at all,
2. its status is `completed`,
3. the caller (`req.uid`) is the `riderId` on that ride, or
4. `distanceMi` / `rideType` match what the ride record actually says.

This is a direct-object-reference / missing-server-side-validation issue — the same class of bug `stripe-backend`'s `ownedRide()` + "never trust a client-supplied value to authorize an action, only to detect a mismatch" rule (index.js:353-359) already exists specifically to prevent, elsewhere in this codebase. `rydr-bank-service` just never adopted that rule.

### What a real ride looks like in Firestore (verified)

The bank service should trust only what is stored on `rides/{rideId}`, so it matters what is there and who writes it:

- **Created** by the driver app when the driver accepts a request, then updated by both apps. Fields the fix needs: `riderId`, `driverId`, `rideType`, `status`, `completedAt`, and `estimatedDistanceMiles` (copied from the rider's route estimate at request time — [FirestoreRideService.swift:107](Features/Booking/FirestoreRideService.swift#L107), [DriverDashboardVM.swift:511-512](RydrDriver/RydrDriver/Features/Dashboard/DriverDashboardVM.swift#L511-L512)). There is no `estimate.distanceMiles` field on the document.
- **`status: "completed"` is written by the driver app** in `completeActiveRide()` ([DriverDashboardVM.swift:901-943](RydrDriver/RydrDriver/Features/Dashboard/DriverDashboardVM.swift#L901-L943)).
- **The rider app only calls `/rides/complete` after it sees that write.** `RideManager.completeRide()` has a single call site, inside the Firestore snapshot handler for `case .completed` ([RideManager.swift:1476-1477](Features/Booking/RideManager.swift#L1476-L1477)). So requiring `status == "completed"` on the server will not reject legitimate rides. (The app calls the endpoint with `try?`, so a rejection would fail silently — no client change is needed for the fix to be safe.)

### Why the lookup alone is not enough (Firestore rules)

Reading [Rydr_Firebase/firestore.rules](Rydr_Firebase/firestore.rules) (`validRiderRideCreate` at line 205, `validRideLifecycleUpdate` at line 269, `match /rides/{rideId}` at line 889): the rules let a **rider** (a) `create` a `rides` document with `riderId == self` and `status == "pending"` and **no restriction on any other field**, and (b) `update` it, because a rider counts as a participant and `status` and `completedAt` are on the update allow-list with **no restriction on the value written**. So, if I've read the rules correctly, a rider with nothing but their own Firebase login can:

1. create `rides/fake-1` with `riderId: <me>`, `rideType: "executive"`, `estimatedDistanceMiles: 999`, `driverId: <anything>`;
2. update it to `status: "completed"`;
3. call `POST /rides/complete { rideId: "fake-1" }` — which would pass every check in a plain "does the ride exist, is it mine, is it completed" lookup.

That is the same attack as today with two extra Firestore writes. **I have not confirmed this against the Firestore emulator** — reproduce it there before relying on this finding or deploying a rules change.

### Recommended correction

**Part A — `rydr-bank-service` (the change you proposed, made concrete).** Replace the trust-the-body approach with a server-side lookup, mirroring the pattern `stripe-backend` already uses for chargeable rides. **All of steps 1-6 are written inline in `rydr-bank-service/server.js`** (tech lead: ride-specific ownership checks stay in the service that owns the ride logic). The shared package supplies only `requireAuth` (who is calling); whether that caller may complete *this ride* is decided here:

1. Load the ride: `db.collection("rides").doc(rideId).get()`. Missing doc → `404`.
2. Check participation: `ride.riderId === req.uid`. Mismatch → `403`, and log it (see [README.md](../README.md#security-logging)) — an authenticated user naming a ride that isn't theirs is the abuse signal worth watching. Only the **rider** earns RydrBank progress (the rider app is the only caller, and accrual is written to the caller's own `users/{uid}`), so a driver naming the same ride also gets `403`.
3. Check ride state: `ride.status === "completed"`, else `409` (mirrors `stripe-backend`'s `CHARGEABLE_RIDE_STATUSES` gate). Also require `ride.driverId` to be set and different from `ride.riderId`, and `ride.completedAt` to exist — cheap sanity checks that a real driver-completed ride satisfies and a lazily forged one may not.
4. **Check the backend-owned financial outcome:** `ride.paymentStatus === "succeeded"`, else `409`. `status === "completed"` says the ride lifecycle finished; `paymentStatus === "succeeded"` says Stripe actually confirmed a charge for it — a stronger, independent signal, and the only one of the two that originates entirely server-side (written by `stripe-backend` via the Admin SDK, never by either app). Reward accrual requires both. (See the Appendix for a related rules finding worth confirming before relying on this field.)
5. Derive `distanceMi` (from `ride.estimatedDistanceMiles`) and `rideType` from the ride document; the route stops reading them from `req.body`. If an older app build still sends them, ignore them (or reject only on mismatch) — never use a body value to decide eligibility. Same "detect, never authorize" rule as `rejectIfSuppliedCustomerMismatch` in `stripe-backend`.
6. Add a **ride-level** idempotency guard inside the same transaction as the reward (e.g. set `rydrBankAccruedAt` on the ride document; skip if already set). Today's only guard is a per-user doc keyed on a client-chosen `rideId` string, which does nothing against a script that changes the id on every call.
7. Add a sanity cap on distance (e.g. reject anything over 150 miles with `422`) as a backstop, and log when it triggers. A stopgap, not a fix — see "Known limitation" below.

With this step, the endpoint's required request body shrinks to just `{ rideId }` — `distanceMi` and `rideType` are derived (step 5), not supplied, and there is nothing left for the client to assert about payment or ride state at all.

**Part B — `firestore.rules` (companion change; needed for Part A to actually hold).** Stop riders from writing the fields the bank service now trusts:

- `rides` `create`, rider path (`validRiderRideCreate`): allow only a small key set and forbid `driverId`, `acceptedDriverId`, `completedAt`, `paymentStatus`, `rydrBankAccruedAt`. First check whether the rider app really uses this path — the normal flow creates the `rides` document from the driver side (`matchingAcceptedRideRequest`). If the rider path is dead code it can be removed instead.
- `rides` `update` (`validRideLifecycleUpdate`): a rider may not set `status` to `"completed"` or write `completedAt` or `rydrBankAccruedAt`; only the ride's driver may write the first two. Riders keep the cancellation fields they use today. (See the Appendix for a related finding about `paymentStatus` on this same allow-list.)
- Test against the Firestore emulator using both apps' real write paths before deploying. This file gates every ride in both iOS apps, so a mistake breaks live rides. It is a bigger, riskier change than Part A and should be reviewed by whoever owns the rules and shipped on its own.

**If Part B can't ship right away:** Part A still removes the *anonymous-body* forgery (no more inventing a ride from nothing in one request) and adds logging, so it is strictly better than today — but describe it as "raises the bar," not "closes the hole," until Part B lands.

**Known limitation, not papered over.** Even with Parts A and B — including the new `paymentStatus` check — the distance is the rider's own client-side routing estimate (`estimatedDistanceMiles`), not a server-measured value, so a rider can still inflate it at request time on a genuinely driver-completed, genuinely paid-for ride. **Requiring `paymentStatus === "succeeded"` does not fix this:** it confirms a real charge happened, not that the distance recorded against that charge is accurate — those are independent facts about the ride. This is a pre-existing data-provenance question (how ride distance is measured or attested) that this proposal doesn't try to solve — worth a follow-up ticket, not an implementation task here. The cap in step 7 limits the damage meanwhile.

---

## Part 3 — Proposed Shared Module

What the package does, its API, error shapes, logging, what it deliberately leaves out, and future upgrades now live in the package's [README.md](../README.md). This part covers only how it gets rolled out.

### Migration guardrail: public routes

- **Intentionally public routes are untouched:** the health checks (`GET /` on all three services, plus `GET /health` on `rydr-backend`), `rydr-backend`'s `/events` routes, `stripe-backend`'s `GET /config`, `POST /webhook`, and the static Stripe Connect return pages `GET /return/complete` and `/return/refresh` (the browser lands there after Stripe onboarding, so they can't require a token), and `rydr-bank-service`'s `POST /web/promo/preview` and `/web/promo/consume`. The last two are how a non-Rydr-user gift recipient redeems a code from the marketing site; they are protected by knowing the code and the email it was sent to, and must not get a Firebase requirement. Each migration PR should list the routes it did *not* wrap, so a reviewer can confirm nothing public got locked and nothing private got left open.

### Gate: how `@rydr/auth-core` reaches each Render build — TESTING, NOT YET CONFIRMED

**No service's *real* imports change until this section is confirmed.** (Tech lead request, still in force.) Status as of October 5, 2026: the package name (`@rydr/auth-core`) and starting path (`file:../shared/rydr-auth`) are now settled by the tech lead. What's still open is whether that path actually survives a Render build for all three services — and the tech lead's follow-up reframed *how* we find out: build the package, test the install/import locally in all three services, then let a Render preview deployment answer the Root Directory question directly, rather than relying on someone reading dashboard settings.

**What Render documents.** From Render's [monorepo docs](https://render.com/docs/monorepo-support): *"Files outside your service's root directory are not available to the service at build time or at runtime."* The same docs say nothing about sharing code between services. So `"@rydr/auth-core": "file:../shared/rydr-auth"` works **only** for a service whose Render Root Directory is empty (the repo root) or set to `shared/`'s parent in a way that keeps `shared/` in scope. Any service with Root Directory set to its own folder (`rydr-backend`, `stripe-backend`, `rydr-bank-service`) will fail `npm install` on its next deploy because `../shared/rydr-auth` does not exist there, taking that service down. Render also does not trigger a build for changes outside the root directory, so a fix inside a folder-external `shared/rydr-auth/` would not redeploy anything by itself.

**What the repo shows (evidence, not confirmation).**

| Service | Live URL | What the repo tells us | What it doesn't |
|---|---|---|---|
| `rydr-backend` | `rydr-backend-2cl9.onrender.com` (from `Info.plist`) | Has `render.yaml` with `buildCommand: npm install`, `startCommand: npm start`, and **no `rootDir`**. | The file sits in `rydr-backend/`, not the repo root, where Render looks by default. Read from the repo root, `npm start` would fail (the root `package.json` has only `resend` and `stripe`, no start script). So either the Blueprint path or a dashboard Root Directory is customized, or this file is not what is actually deployed. |
| `stripe-backend` | `rydr-stripe-backend.onrender.com` | Own `package.json` with `"start": "node index.js"`. | Nothing about how Render is configured. `RYDR_BETA_READINESS_PUNCHLIST.md` says config lives only in the Render dashboard (that note predates `rydr-backend/render.yaml`, so it is at best partly stale). |
| `rydr-bank-service` | `rydr-bank.onrender.com` | `"main": "index.js"` but the file is `server.js`, and there is no `start` script — so the live start command must be set in the dashboard, meaning the dashboard config is real and unversioned. | Root Directory, build command, start command. |

Reasonable inference: a repo root with no start script and three separately-scoped services suggests each has a Root Directory set. That would break `file:../shared/rydr-auth`. It is an inference; treat it as unconfirmed — which is exactly why the primary method below doesn't depend on it.

**Primary method to close this gate (tech lead's ask):**

1. **Build `shared/rydr-auth/`** per the layout in [README.md](../README.md) — no service wiring changes, just the package itself plus its own tests.
2. **Add the dependency to all three `package.json` files** (`"@rydr/auth-core": "file:../shared/rydr-auth"`), run `npm install` in each service **locally**, and confirm the `package-lock.json` gets a `file:` entry for it without errors.
3. **Smoke-test the import in each service**, without touching any real route: a throwaway script (or a one-off test file) that does `require("@rydr/auth-core")` from `rydr-backend` and `stripe-backend` (CommonJS) and `import rydrAuthCore from "@rydr/auth-core"` from `rydr-bank-service` (ESM), and calls `createAuth({ admin })` with a fake `admin` to confirm the shape is right. This is the "test locally" half of the ask.
4. **Push a branch with those three `package.json`/`package-lock.json` changes (and the new `shared/rydr-auth/` folder) and trigger a Render preview deployment** for all three services. This is the "confirm it works in a Render preview deployment" half. The outcome is unambiguous either way:
   - All three preview builds succeed → Root Directory is not scoping out `shared/`, `file:../shared/rydr-auth` is confirmed, proceed with it.
   - Any preview build fails `npm install` with a path/`ENOENT`-style error on `../shared/rydr-auth` → that service's Root Directory is scoped to its own folder, confirming the inference above. Move to the fallback row below for that service (possibly only that one, not all three).
5. **Optional cross-check:** if dashboard access is available, reading each service's *Settings → Root Directory* directly (and Build/Start Command, repo/branch, Node version, whether a Blueprint manages it) confirms the same thing without needing a throwaway deploy. Useful as a second source, not required to proceed — the preview deploy in step 4 is the authoritative test either way.

**Decision once confirmed.**

| Result | Approach |
|---|---|
| All three preview builds succeed (empty Root Directory / `shared/` in scope) | `file:../shared/rydr-auth` works. |
| Any service's preview build fails (its own folder as Root Directory) | Tech lead named two alternatives for that service, either is viable: (a) **vendored copy** — `shared/rydr-auth/` copied into the service as `vendor/rydr-auth` (`"@rydr/auth-core": "file:./vendor/rydr-auth"`), with a script and a test that fail if the copies differ; everything is inside the root directory, so it builds anywhere and edits trigger a redeploy, at the cost of copies to keep in sync; or (b) **private npm package or Git dependency** — publish `@rydr/auth-core` to a private registry (or point `package.json` at a Git URL/subdirectory) so `npm install` fetches it independently of the service's Root Directory, at the cost of a publish/tag step on every change instead of an in-repo edit. Vendoring is less infrastructure to stand up; a private package/Git dependency is more "normal npm" if more services are expected to consume this later. Worth a short discussion with the tech lead once a failure is actually seen, rather than deciding both branches in advance. |
| Nobody can confirm before the work needs to start | Default to the vendored copy — it is correct under either configuration and needs no new infrastructure. Changing the Render Root Directory on live services, or standing up a private registry, just to suit this package is a bigger change than three synced copies, and is the tech lead's call, not part of this project. |

Also required before the first `@rydr/auth-core` migration PR: the `package-lock.json` entry for the `file:` dependency must be committed in all three services, and the Render preview deploy from step 4 above **is** that check — it should be green before merge, not discovered on `main`.

### Automated authentication tests

None of the three services has any tests today (no test dependency in any `package.json`; `rydr-bank-service`'s `test` script is the `npm init` placeholder that exits 1; `stripe-backend`'s is only `node --check`). Proposed, using only what ships with Node 18+ (`node:test`, `node:assert`, built-in `fetch`) — **no jest, mocha or supertest to install**:

- **`shared/rydr-auth/tests/`** — unit tests with a fake `admin`: missing header → 401; malformed header → 401; verify throws (invalid/expired) → 401 and the token is not in the logs; valid token → `req.user` set; admin claim / non-admin → pass / 403; driver doc exists / missing → pass / 403; internal secret right / wrong / unset; `assertOwnsUid` match / mismatch / missing → pass / 403 / 403; logger never emits fields outside its allow-list.
- **Per service, one small `auth.test.js`** that boots the Express app on an ephemeral port with the fake `admin` and checks: no token → 401; wrong owner or role → 403; correct token → success; and the intentionally public routes still work with no token.
- **`rydr-bank-service` needs one small refactor to be testable at all.** `server.js` initializes Firebase from a credential file at import time and calls `app.listen` at the bottom, so it can't be imported into a test. Moving `app` creation into a function that takes `db` and `auth` (leaving `server.js` as the thin entry point that wires up the real ones) is the whole change. `/rides/complete` then gets regression tests for Part 2: nonexistent ride → 404; another rider's ride → 403; driver naming the ride → 403; ride not `completed` → 409; `paymentStatus` not `"succeeded"` (missing, `"pending"`, `"failed"`) → 409; forged body distance/rideType ignored; same ride replayed → second call earns nothing; over-cap distance → 422; happy path (`status: "completed"` + `paymentStatus: "succeeded"`) → 200 with one accrual.

### Suggested rollout order

0. **Close the Render gate**: build `shared/rydr-auth/`, add the `file:` dependency to all three `package.json` files, test the install/import locally, then push a branch and confirm via a Render preview deployment (primary method above), choosing `file:../shared/rydr-auth`, `vendor/rydr-auth`, or a private package/Git dependency per the result. **No *real* route imports change before this.** Then run the `stripe-backend/node_modules` cleanup commit (1d).
1. Finish `shared/rydr-auth` + its tests (beyond the smoke test used to close the gate). No running service changes yet.
2. Migrate `rydr-backend` (closest to the target shape, lowest risk).
3. Migrate `stripe-backend`, keeping the shared-secret admin path behaving identically. Its `500 firebase_admin_misconfigured` response is kept.
4. `rydr-bank-service`: testability refactor, migrate its auth, and fix `/rides/complete` (Part 2, Part A) in one change.
5. `firestore.rules` tightening (Part 2, Part B) — **separate PR, emulator-tested, reviewed by the rules owner.** Steps 4 and 5 should land close together; until step 5 lands, the fix raises the bar but doesn't fully close the hole.
6. Migrate the remaining `rydr-bank-service` promo routes.

Each step ships with its tests before the next begins, so a regression in step 2 isn't compounded by 3-6 built on top of it.

---

## Appendix — Additional Finding to Raise With the Tech Lead (Not Part of This Proposal)

Found while checking whether `ride.paymentStatus` is trustworthy enough to gate on (Part 2, Part A, step 4). This is a live gap in `firestore.rules` today, independent of whether `/rides/complete` ever gets fixed — flagging it separately rather than folding it into the proposal above, since it needs its own decision, not a vote on this project.

**`paymentStatus` is currently just as forgeable as `status` was.** `rides/{rideId}.paymentStatus` (`"pending" | "processing" | "succeeded" | "failed" | "refunded"`) is meant to be written only by `stripe-backend`'s `recordPaymentStatus()` ([stripe-backend/index.js:913](stripe-backend/index.js#L913)), via the Firebase Admin SDK after Stripe actually confirms a charge — it's the real record of money moving, not a status flag either app writes. But today's rules put it on `validRideLifecycleUpdate`'s allow-list ([firestore.rules:314](Rydr_Firebase/firestore.rules#L314)) with **no restriction on the value a participant writes** — the same gap `status`/`completedAt` had before this proposal. So a rider could write `paymentStatus: "succeeded"` on their own ride document directly, no different from forging `status: "completed"` today.

This codebase already knows to forbid it: `validCashHubRequestCreate()` and `validCashHubConversationCreate()` both explicitly block client writes to `paymentStatus` on the `cashRydrRequests`/`cashHubConversations` collections ([firestore.rules:443](Rydr_Firebase/firestore.rules#L443), [firestore.rules:520](Rydr_Firebase/firestore.rules#L520)) — the `rides` collection is the one place that pattern wasn't applied.

**Why it matters for this proposal specifically:** if Part A's new step 4 checks `ride.paymentStatus === "succeeded"` without this gap also being closed, that check is cosmetic — a rider can satisfy it the same way they can satisfy `status === "completed"` today. For the financial-outcome check to actually mean anything, `paymentStatus` needs the same treatment Part B already proposes for `status`/`completedAt`: remove it from `validRideLifecycleUpdate`'s allow-list entirely (it has no legitimate client-side writer at all, unlike `status`, which the driver legitimately writes).

**Not included in Part B above because:** it's a separate conversation from "should we build the shared auth layer and fix `/rides/complete`" — worth raising with the tech lead on its own, possibly as its own small rules PR, rather than letting it ride in on this proposal's scope.
