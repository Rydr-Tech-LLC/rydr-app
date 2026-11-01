# Current Task — `@rydr/auth-core`

**Updated:** November 1, 2026
**Requested by:** tech lead
**Branch:** `BUG-017-Duplicated-Authentication-Logic`

Two things to finish before the Render preview deployment:

1. Write the **package's own tests**, so the package is known to work before any service installs it.
2. Confirm all three services can **install and import** the package locally.

No service routes change as part of this task (ADR-004). See [README.md](../README.md) for what the package does and [Architecture Decision Records.md](Architecture%20Decision%20Records.md) for why.

---

## Task 1 — Package tests

**Goal:** cover every behavior the README documents, so a change that breaks auth fails a test instead of reaching a service.

**Rules (ADR-013):** Node's built-in runner only (`node:test`, `node:assert`) — no jest, mocha or supertest. Use a fake `admin` object, never a real Firebase project. Files go in `shared/rydr-auth/tests/`, named `*.test.js` so `node --test` finds them. Run with `npm test` from `shared/rydr-auth/`.

### Test files and cases

**`tests/verifyToken.test.js` — `requireAuth`**
- [x] No `Authorization` header → 401, logs `token_missing`
- [x] Malformed header (not `Bearer <token>`) → 401
- [x] `verifyIdToken` throws → 401, logs `token_invalid` with the error code only
- [x] The raw token never appears in any log output
- [x] Valid token → `next()` called, `req.user = { uid, claims }`, `req.firebaseUid` and `req.uid` set

**`tests/roles.test.js` — `requireDriver`**
- [x] `drivers/{uid}` exists → `next()`
- [x] Document missing → 403 `"driver account required"`, logs `role_denied`
- [x] Firestore lookup throws → 403, logs `role_check_error`
- [x] No `req.user` → 401 `"Authentication required before role check"`

**`tests/roles.test.js` — `requireAdmin`**
- [x] Token with `admin: true` → `next()`, `req.user` set
- [x] Token with `role: "admin"` → `next()`
- [x] Token without an admin claim → 403 `"admin_required"`, logs `role_denied`
- [x] No / malformed header → 401
- [x] `verifyIdToken` throws → 401, logs `token_invalid`
- [x] `allowInternalSecret: true` + correct secret → `next()`, `req.user.uid` from `x-admin-uid`
- [x] Correct secret, no `x-admin-uid` → `req.user.uid === "mission-control"`
- [x] Wrong secret → falls through to the token check
- [x] `RYDR_INTERNAL_ADMIN_SECRET` unset → secret path never grants access
- [x] `allowInternalSecret` false (default) → secret header ignored

**`tests/ownership.test.js` — `assertOwnsUid`**
- [x] Matching uid → returns `true`, no response sent
- [x] Mismatched uid → returns `false`, 403, logs `ownership_mismatch`
- [x] No `req.user` → returns `false`, 403
- [x] Log entry includes `route` (guards the `originalUrl` typo fixed on Oct 26)

**`tests/responses.test.js`**
- [x] `unauthorized()` → 401 `{ error: "unauthorized", message }`
- [x] `forbidden()` → 403 `{ error: "forbidden", message }`

**`tests/logger.test.js` — `logAuthEvent`**
- [x] Only `event`, `uid`, `route`, `reason`, `code` are written; any other field is dropped
- [x] Undefined fields are left out
- [x] Each entry has an `at` timestamp

**`tests/index.test.js` — `createAuth`**
- [x] Returns exactly `requireAuth`, `requireDriver`, `requireAdmin`, `assertOwnsUid`
- [x] Loads through `require` (CommonJS) and `import` (ESM, named and default)

**Status (Nov 1):** written and passing — 37 tests across 7 files, using mock data from `tests/helpers.js`. Committed Nov 1.

### Done when

- [x] All files above exist and `npm test` passes
- [x] `tests/` is committed (git doesn't track the empty folder until it has a file)
- [x] README "Testing" section updated if anything about how to run tests changed

---

## Task 2 — Local install and import

**Goal:** show that `"@rydr/auth-core": "file:../shared/rydr-auth"` installs cleanly and loads in each service, using that service's own module system.

### Steps, per service

| Service | Module system | Import check |
|---|---|---|
| `rydr-backend` | CommonJS | `require` |
| `stripe-backend` | CommonJS | `require` |
| `rydr-bank-service` | ESM (`"type": "module"`) | `import` |

1. From the service folder, install:
   ```
   npm install ../shared/rydr-auth
   ```
   This adds `"@rydr/auth-core": "file:../shared/rydr-auth"` to `package.json` and an entry with `"link": true` to `package-lock.json`.

2. Check the import, without touching any route:
   - CommonJS (`rydr-backend`, `stripe-backend`):
     ```
     node -e "const { createAuth } = require('@rydr/auth-core'); console.log(Object.keys(createAuth({ admin: {} })))"
     ```
   - ESM (`rydr-bank-service`) — check both forms:
     ```
     node --input-type=module -e "import { createAuth } from '@rydr/auth-core'; console.log(Object.keys(createAuth({ admin: {} })))"
     node --input-type=module -e "import rydrAuthCore from '@rydr/auth-core'; console.log(Object.keys(rydrAuthCore.createAuth({ admin: {} })))"
     ```
   Expected output: `[ 'requireAuth', 'requireDriver', 'requireAdmin', 'assertOwnsUid' ]`

3. Record the result in the checklist below.

### Before you start

- **`stripe-backend` has `node_modules` committed to git** (1,225 tracked files). Running `npm install` there changes tracked files. Either get the tech lead's OK to do the cleanup commit first (`git rm -r --cached stripe-backend/node_modules`), or run `git status` after installing and expect `node_modules` changes in the diff.
- **Removing the install safely:** `node_modules/@rydr/auth-core` is a Windows junction (a folder shortcut) pointing at `shared/rydr-auth`. Delete the junction on its own first, then `node_modules`. Some delete commands follow a junction and would delete the package source.
- **Keep the `package.json` / `package-lock.json` changes** once all three pass. They are what the Render preview deployment builds from. Don't merge them to `main` until the preview confirms them.

### Checklist

- [ ] `rydr-backend` — installs
- [ ] `rydr-backend` — `require` returns the four functions
- [ ] `stripe-backend` — installs (node_modules diff checked)
- [ ] `stripe-backend` — `require` returns the four functions
- [ ] `rydr-bank-service` — installs
- [ ] `rydr-bank-service` — named `import` returns the four functions
- [ ] `rydr-bank-service` — default `import` returns the four functions
- [ ] Results shared with tech lead

---

## After this task

1. Commit the package, its tests, and the three services' `package.json` / `package-lock.json` changes on the branch.
2. Push and confirm all three services build in a **Render preview deployment** (proposal, Part 3, "Gate").
3. Mark ADR-004 Accepted once all three pass.
