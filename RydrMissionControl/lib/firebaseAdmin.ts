import "server-only";
import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

/**
 * Server-only Firebase Admin SDK singleton. This is what every privileged
 * write in Mission Control goes through (driver approval, suspensions,
 * report actions, audit log entries) — it runs with full backend
 * credentials and is the ONLY thing in this app allowed to set
 * backend-owned fields like `driverApprovalStatus`, `approvedAt`,
 * `approvedBy`, etc. The browser never touches these directly.
 *
 * Initialization (and the env-var check below) is intentionally lazy: it
 * must NOT run at module-import time, because Next.js imports this module
 * while statically collecting page/route data during `next build` — long
 * before any real request exists and long before Vercel env vars are
 * necessarily configured. `adminAuth`/`adminDb` are Proxies that only
 * construct the real Admin SDK objects the first time a route handler or
 * server component actually calls a method on them at runtime.
 */
let cachedApp: App | null = null;

function buildAdminApp(): App {
  if (getApps().length) return getApps()[0]!;

  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY?.replace(/\\n/g, "\n");

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      "Missing Firebase Admin credentials. Set FIREBASE_ADMIN_PROJECT_ID, " +
        "FIREBASE_ADMIN_CLIENT_EMAIL, and FIREBASE_ADMIN_PRIVATE_KEY (see .env.example)."
    );
  }

  return initializeApp({
    credential: cert({ projectId, clientEmail, privateKey })
  });
}

function getAdminApp(): App {
  if (!cachedApp) cachedApp = buildAdminApp();
  return cachedApp;
}

/**
 * Wraps a factory in a Proxy so the wrapped SDK object (Auth/Firestore) is
 * only constructed the first time a property is actually accessed. Methods
 * are returned pre-bound to the real instance so `this` inside the SDK's
 * own implementation is correct no matter how the caller invokes them
 * (e.g. `adminDb.collection(...)` — the call site's `this` would otherwise
 * be the Proxy itself, not the real Firestore instance).
 */
function lazy<T extends object>(factory: () => T): T {
  let instance: T | null = null;
  const ensure = (): T => {
    if (!instance) instance = factory();
    return instance;
  };

  return new Proxy({} as T, {
    get(_target, prop, _receiver) {
      const real = ensure();
      const value = Reflect.get(real as object, prop, real);
      return typeof value === "function" ? value.bind(real) : value;
    },
    has(_target, prop) {
      return Reflect.has(ensure() as object, prop);
    }
  });
}

export const adminAuth: Auth = lazy(() => getAuth(getAdminApp()));
export const adminDb: Firestore = lazy(() => getFirestore(getAdminApp()));
