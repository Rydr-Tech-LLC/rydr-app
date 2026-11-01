# Architecture Decision Records — `@rydr/auth-core`

One entry per decision about the shared auth package and the `/rides/complete` fix. Each records what was decided, why, and what follows from it. Detailed reasoning and evidence live in [AUTH_LAYER_AUDIT_AND_PROPOSAL.md](AUTH_LAYER_AUDIT_AND_PROPOSAL.md); how the package behaves lives in [README.md](../README.md).

**Statuses:** *Accepted* — decided and in effect. *Accepted, pending verification* — decided, but depends on a check not yet done. *Superseded* — replaced by a later record.

To add a decision: append a new number (never renumber), and if it replaces an earlier one, mark the earlier one *Superseded by ADR-0NN* rather than deleting it.

## Index

| # | Decision | Status | Date |
|---|---|---|---|
| [001](#adr-001-one-shared-internal-package-for-auth) | One shared internal package for auth | Accepted | 2026-09-16 |
| [002](#adr-002-package-name-and-location) | Package name `@rydr/auth-core`, located at `shared/rydr-auth` | Accepted | 2026-10-05 |
| [003](#adr-003-ride-specific-ownership-stays-in-the-owning-service) | Ride-specific ownership stays in the owning service | Accepted | 2026-09-18 |
| [004](#adr-004-no-service-imports-change-until-the-render-build-is-confirmed) | No service imports change until the Render build is confirmed | Accepted, pending verification | 2026-09-18, revised 2026-10-05 |
| [005](#adr-005-one-commonjs-build-for-both-commonjs-and-esm-services) | One CommonJS build for both CommonJS and ESM services | Accepted | 2026-10-26 |
| [006](#adr-006-services-pass-in-their-own-firebase-admin) | Services pass in their own `firebase-admin` | Accepted | 2026-09-16 |
| [007](#adr-007-roles-come-from-existing-data-not-new-custom-claims) | Roles come from existing data, not new custom claims | Accepted | 2026-09-18 |
| [008](#adr-008-requireadmin-verifies-the-token-itself) | `requireAdmin` verifies the token itself | Accepted | 2026-10-26 |
| [009](#adr-009-internal-admin-secret-uses-plain--for-now) | Internal admin secret uses plain `===` for now | Accepted | 2026-10-26 |
| [010](#adr-010-one-requser-shape-with-temporary-aliases) | One `req.user` shape, with temporary aliases | Accepted | 2026-09-16 |
| [011](#adr-011-one-standard-401--403-response-shape) | One standard 401 / 403 response shape | Accepted | 2026-09-16 |
| [012](#adr-012-fixed-field-security-logging-failures-only) | Fixed-field security logging, failures only | Accepted | 2026-09-16 |
| [013](#adr-013-tests-use-only-nodes-built-in-test-runner) | Tests use only Node's built-in test runner | Accepted | 2026-09-18 |
| [014](#adr-014-ridescomplete-trusts-only-the-stored-ride-and-payment-outcome) | `/rides/complete` trusts only the stored ride and payment outcome | Accepted | 2026-09-16, revised 2026-10-19 |
| [015](#adr-015-firestore-rules-tightening-ships-as-its-own-pr) | Firestore rules tightening ships as its own PR | Accepted | 2026-09-18 |

---

## ADR-001: One shared internal package for auth

- **Status:** Accepted
- **Date:** 2026-09-16

**Context.** `rydr-backend`, `stripe-backend` and `rydr-bank-service` each implement Firebase ID token verification separately. The copies have drifted: three different 401 shapes, no shared role/admin model, no shared logging rules, and no tests. (Proposal, Part 1.)

**Decision.** Extract the duplicated, universal parts into one small internal package: Bearer parsing, Firebase token verification, claims/roles, standard errors, and safe security logging.

**Consequences.** One place to fix auth bugs and add tests. Each service takes on a dependency it has to install at build time (see ADR-004). Anything domain-specific stays out (see ADR-003).

---

## ADR-002: Package name and location

- **Status:** Accepted (tech lead)
- **Date:** 2026-10-05 — supersedes the September name `@rydr/auth` and top-level `rydr-auth/` folder

**Context.** The first drafts used `@rydr/auth` in a top-level `rydr-auth/` folder.

**Decision.** Name the package `@rydr/auth-core` and place it at `shared/rydr-auth/`. Services depend on it with `"@rydr/auth-core": "file:../shared/rydr-auth"` as the starting point.

**Consequences.** The `file:` path only works if each service's Render build can see `shared/`. That is still being confirmed (ADR-004), so the path may change; the package name will not.

---

## ADR-003: Ride-specific ownership stays in the owning service

- **Status:** Accepted (tech lead)
- **Date:** 2026-09-18

**Context.** The first draft proposed a generic `loadOwnedDoc(db, collection, id, ownerField, uid)` helper in the shared package, for `/rides/complete`.

**Decision.** Removed it. The package only knows about *users* (uid, role), never about rides, payments or promo codes. "Does this caller own this ride, and is it in a state that earns a reward?" is business logic that stays in the service that owns it: `rydr-bank-service` for `/rides/complete`, and `stripe-backend` keeps `ownedRide()` and its payment helpers. The package's only ownership helper, `assertOwnsUid`, is a plain uid comparison.

**Consequences.** The shared package isn't coupled to any one service's data model. Similar ownership lookups may be repeated across services; if a second service ends up copy-pasting the same one, reconsider a generic helper with that service's owner.

---

## ADR-004: No service imports change until the Render build is confirmed

- **Status:** Accepted, pending verification (tech lead)
- **Date:** 2026-09-18; method revised 2026-10-05

**Context.** Render's monorepo docs say files outside a service's Root Directory aren't available at build or run time. If any service's Root Directory is its own folder, `file:../shared/rydr-auth` fails `npm install` and takes that service down on its next deploy. The repo doesn't show how the three services are configured on Render.

**Decision.**
- No service's real imports change until the install path is confirmed for each service.
- Confirm it by testing the install and import locally in all three services, then pushing a branch and letting a Render preview deployment build all three. Reading each service's Root Directory setting in the dashboard is an optional cross-check, not the primary method (revised 2026-10-05 per tech lead).
- If a service's preview build fails, use one of the tech lead's two alternatives for that service: a vendored copy (`file:./vendor/rydr-auth`, with a check that fails if the copies differ), or a private npm package / Git dependency. If nobody can confirm before work has to start, default to the vendored copy.

**Consequences.** This is rollout step 0. The `package-lock.json` entry for the dependency must be committed in each service, and the preview deploy must be green before merge. Details: proposal, Part 3, "Gate."

---

## ADR-005: One CommonJS build for both CommonJS and ESM services

- **Status:** Accepted (requirement from tech lead; approach verified 2026-10-26)
- **Date:** 2026-10-26

**Context.** The tech lead required the package to support both module systems: `rydr-backend` and `stripe-backend` are CommonJS, and `rydr-bank-service` is ESM (`"type": "module"`).

**Decision.** Write the package as plain CommonJS with no build step. ESM services import it through Node's ESM-to-CommonJS interop. Both `import { createAuth } from "@rydr/auth-core"` and `import rydrAuthCore from "@rydr/auth-core"` were verified on Node 20.17.

**Consequences.** One output to maintain. `index.js` must keep ending in the plain `module.exports = { createAuth }` form; that's what lets Node detect `createAuth` as a named export for ESM callers.

---

## ADR-006: Services pass in their own `firebase-admin`

- **Status:** Accepted
- **Date:** 2026-09-16

**Context.** Each service already initializes Firebase Admin with its own credentials and env-var loading. If the package imported `firebase-admin` itself, it could get a separate, uninitialized copy.

**Decision.** The package never imports `firebase-admin` and never touches credentials. Each service passes its initialized instance once: `createAuth({ admin })`. Firebase initialization stays per service; unifying it is a separate, riskier change.

**Consequences.** Tests can pass in a small fake `admin` instead of a real Firebase project. `stripe-backend` initializes Firebase lazily, so it must initialize before calling `createAuth` or before its admin route runs.

---

## ADR-007: Roles come from existing data, not new custom claims

- **Status:** Accepted
- **Date:** 2026-09-18 — corrects the first draft, which made a `role: "driver"` claim a prerequisite

**Context.** The codebase already has ways to tell drivers and admins apart. Adding new custom claims would be a prerequisite migration.

**Decision.**
- *Rider* = any authenticated user. No route is rider-only today, and `riders/{uid}` only exists after a Stripe customer is created, so it can't be the gate.
- *Driver* = a `drivers/{uid}` document exists in Firestore (`requireDriver`), which is how `stripe-backend` already decides.
- *Admin* = token claim `admin === true` or `role === "admin"` (`requireAdmin`), matching `isAdmin()` in `firestore.rules` and `stripe-backend`'s `requireAdminUid`.

**Consequences.** No new claims to set up. `requireDriver` costs one Firestore read per request, and fails closed (403) if that read throws.

---

## ADR-008: `requireAdmin` verifies the token itself

- **Status:** Accepted
- **Date:** 2026-10-26

**Context.** `stripe-backend`'s admin route (`POST /admin/cleanup-account`) has no auth middleware in front of it, and Mission Control calls it server-to-server with a shared secret instead of a Firebase token.

**Decision.** `requireAdmin({ allowInternalSecret })` is a factory that returns middleware that does its own work: it checks the internal secret (if allowed), otherwise reads and verifies the Bearer token itself. It doesn't depend on `requireAuth` having run. The decision logic matches `requireAdminUid`; only the response bodies change, to the standard shape (ADR-011).

**Consequences.** It works on `stripe-backend`'s route as-is. Unlike `requireDriver`, it doesn't need `requireAuth` first, which the README calls out.

---

## ADR-009: Internal admin secret uses plain `===` for now

- **Status:** Accepted
- **Date:** 2026-10-26 — replaces the earlier plan to switch to `crypto.timingSafeEqual` during the migration

**Context.** `stripe-backend` compares `x-internal-admin-secret` to `RYDR_INTERNAL_ADMIN_SECRET` with `===`. An earlier version of the plan made a constant-time comparison the one deliberate behavior change in the migration.

**Decision.** Keep the plain `===` so the shared package behaves exactly like the code it replaces. The constant-time comparison is listed under "Future upgrades" in the README.

**Consequences.** The migration changes no security behavior. The upgrade should be its own small PR afterward, so it's the only behavior change in that diff.

---

## ADR-010: One `req.user` shape, with temporary aliases

- **Status:** Accepted
- **Date:** 2026-09-16

**Context.** The services spell the authenticated user three ways: `req.uid`, `req.firebaseUid`, and ad hoc `uid` locals.

**Decision.** `requireAuth` sets `req.user = { uid, claims }`. It also sets `req.firebaseUid` and `req.uid` as aliases until every service is migrated.

**Consequences.** Existing route code keeps working mid-migration. The aliases should be removed once all callers use `req.user.uid`.

---

## ADR-011: One standard 401 / 403 response shape

- **Status:** Accepted
- **Date:** 2026-09-16

**Context.** The three services return three different 401 bodies.

**Decision.** Use `401 { error: "unauthorized", message }` and `403 { error: "forbidden", message }` everywhere. The only client check on these strings is `case "unauthorized"` in `RiderIdentityVerificationService.swift`, which `stripe-backend` already returns, and no client reads `"admin_required"`.

**Consequences.** The apps aren't affected. `stripe-backend`'s separate `500 firebase_admin_misconfigured` stays, since bad server credentials are a different failure from a bad token.

---

## ADR-012: Fixed-field security logging, failures only

- **Status:** Accepted
- **Date:** 2026-09-16

**Context.** Logging a request, token or error object can leak a bearer token, a decoded ID token (which contains email/phone) or a request body.

**Decision.** All package logging goes through `logAuthEvent`, which accepts only `event`, `uid`, `route`, `reason` and `code`. Failed authentication and every 403 are logged; successful requests are not. From the Firebase error, only `err.code` is logged.

**Consequences.** A future caller can't accidentally log sensitive data through the package. 403 logs become the signal that would have made `/rides/complete` abuse visible.

---

## ADR-013: Tests use only Node's built-in test runner

- **Status:** Accepted
- **Date:** 2026-09-18

**Context.** None of the three services has tests or a test dependency today. The goal was "nothing too complicated."

**Decision.** Use only what ships with Node 18+ (`node:test`, `node:assert`, built-in `fetch`). No jest, mocha or supertest. Package tests live in `shared/rydr-auth/tests/`, one `*.test.js` file per module, with a fake `admin`.

**Consequences.** Nothing to install. `rydr-bank-service` needs one small refactor (app creation moved into a function that takes `db` and `auth`) before it can be tested at all.

---

## ADR-014: `/rides/complete` trusts only the stored ride and payment outcome

- **Status:** Accepted (tech lead: "your proposed checks are correct")
- **Date:** 2026-09-16; payment check added 2026-10-19

**Context.** `rydr-bank-service`'s `/rides/complete` accrues RydrBank rewards from `rideId`, `distanceMi` and `rideType` sent in the request body, with no check that the ride exists, is complete, or belongs to the caller. (Proposal, Part 2.)

**Decision.** Rewrite the route, inline in `rydr-bank-service` (per ADR-003), to load the canonical ride and decide from stored fields only:
1. Ride must exist (else 404).
2. Caller must be the ride's rider (else 403, logged).
3. Ride must be `completed`, with a driver set (different from the rider) and `completedAt` present (else 409).
4. `paymentStatus` must be `"succeeded"` (else 409) — added 2026-10-19 after the tech lead asked for the backend financial outcome, not just a status flag.
5. Distance and ride type come from the ride document, never the body.
6. A ride-level idempotency guard in the same transaction as the reward.
7. A distance sanity cap (422) as a backstop.

**Consequences.** The request body shrinks to `{ rideId }`. The fix only fully holds once riders can't write those fields themselves (ADR-015). Distance is still the rider's own routing estimate; how distance is measured is a separate follow-up.

---

## ADR-015: Firestore rules tightening ships as its own PR

- **Status:** Accepted
- **Date:** 2026-09-18

**Context.** Today's `firestore.rules` let a rider create and complete their own ride document, so a server-side lookup alone can be satisfied with two extra Firestore writes. (Proposal, Part 2, "Why the lookup alone is not enough." Not yet reproduced against the emulator.)

**Decision.** Tighten the rules so riders can't write `driverId`, `completedAt`, `rydrBankAccruedAt`, or set `status` to `"completed"`. Ship it as a separate PR: emulator-tested against both apps' real write paths, reviewed by the rules owner, and landed close to the `/rides/complete` fix.

**Consequences.** Until it lands, the bank-service fix "raises the bar" but doesn't close the hole. The related `paymentStatus` rules gap is a separate item to raise with the tech lead (proposal, Appendix), not part of this decision.
