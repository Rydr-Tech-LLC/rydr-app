# Rydr Firebase backend

This is the Firebase CLI root for Rydr. It owns Cloud Functions, Firestore
rules and indexes, Storage rules, and rules tests.

Run Firebase commands from this directory:

```bash
firebase login --reauth
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Validation:

```bash
npm ci
firebase emulators:exec --only firestore "npm run test:rules"
npm --prefix functions ci
npm --prefix functions run build
```

The current Firebase Emulator Suite requires JDK 21 or newer. Production
deploys do not use the local emulator, but rules tests will not start on an
older Java runtime.

Supporting guides are in `docs/`. Do not commit `.env` files, Firebase debug
logs, service-account JSON, or generated `functions/lib` output.
