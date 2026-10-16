import * as firestore from "firebase-functions/v2/firestore";
import * as https from "firebase-functions/v2/https";
import * as scheduler from "firebase-functions/v2/scheduler";
import * as storage from "firebase-functions/v2/storage";
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { runInWorkspace } from "./services/workspaceRuntime";
import {
  accountWorkspace,
  workspaceDefinition,
} from "./services/workspacePolicy";
const liveHandlers = new Map<unknown, unknown>();
function app() {
  return getApps().find((a) => a.name === "[DEFAULT]") ?? initializeApp();
}
async function assertWorkspace(uid: string, workspace: string, admin = false) {
  if (admin) return;
  const user = await getAuth(app()).getUser(uid);
  if (user.disabled)
    throw new https.HttpsError("unauthenticated", "Account disabled");
  const policy = (
    await getFirestore(app())
      .collection("operationalSecurity")
      .doc("liveBetaAccess")
      .get()
  ).data();
  if (accountWorkspace(uid, user.phoneNumber, policy) !== workspace)
    throw new https.HttpsError(
      "permission-denied",
      "Account belongs to a different workspace",
    );
}
function dual(
  factory: any,
  args: any[],
  kind: "firestore" | "callable" | "http" | "schedule",
) {
  const options =
    typeof args[0] === "function"
      ? {}
      : typeof args[0] === "string"
        ? kind === "schedule"
          ? { schedule: args[0] }
          : { document: args[0] }
        : { ...args[0] };
  const callback = args.at(-1);
  const create = (workspace: "test" | "live-beta") => {
    const opts = {
      ...options,
      ...(kind === "firestore"
        ? { database: workspaceDefinition(workspace).databaseId }
        : {}),
    };
    return factory(opts, async (...values: any[]) =>
      runInWorkspace(workspace, async () => {
        if (kind === "callable" && values[0].auth)
          await assertWorkspace(
            values[0].auth.uid,
            workspace,
            values[0].auth.token.admin === true ||
              values[0].auth.token.role === "admin",
          );
        if (kind === "schedule" && workspace === "live-beta") {
          const state = (
            await getFirestore(app(), "live-beta")
              .collection("platformConfig")
              .doc("workspace")
              .get()
          ).data();
          if (state?.enabled !== true || state.livePaymentsEnabled !== true)
            return;
        }
        return callback(...values);
      }),
    );
  };
  const test = create("test"),
    live = create("live-beta");
  liveHandlers.set(test, live);
  return test;
}
export const onDocumentWritten = ((...args: any[]) =>
  dual(
    firestore.onDocumentWritten,
    args,
    "firestore",
  )) as typeof firestore.onDocumentWritten;
export const onDocumentCreated = ((...args: any[]) =>
  dual(
    firestore.onDocumentCreated,
    args,
    "firestore",
  )) as typeof firestore.onDocumentCreated;
export const onDocumentUpdated = ((...args: any[]) =>
  dual(
    firestore.onDocumentUpdated,
    args,
    "firestore",
  )) as typeof firestore.onDocumentUpdated;
export const onSchedule = ((...args: any[]) =>
  dual(scheduler.onSchedule, args, "schedule")) as typeof scheduler.onSchedule;
export const onCall = ((...args: any[]) =>
  dual(https.onCall, args, "callable")) as typeof https.onCall;
export const onRequest = ((...args: any[]) =>
  dual(https.onRequest, args, "http")) as typeof https.onRequest;
// Storage remains shared, but the verified owner determines the review database.
export const onObjectFinalized = ((options: any, callback: any) =>
  storage.onObjectFinalized(options, async (event: any) => {
    const name = String(event.data?.name ?? "");
    const match = name.match(
      /^(driverDocuments|riderDocuments|riderVerificationDocuments)\/([^/]+)\//,
    );
    if (!match) return;
    let user;
    try {
      user = await getAuth(app()).getUser(match[2]);
    } catch {
      return;
    }
    if (user.disabled) return;
    const policy = (
      await getFirestore(app())
        .collection("operationalSecurity")
        .doc("liveBetaAccess")
        .get()
    ).data();
    return runInWorkspace(
      accountWorkspace(user.uid, user.phoneNumber, policy),
      () => callback(event),
    );
  })) as typeof storage.onObjectFinalized;
export function liveWorkspaceHandlers(exports: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(exports)
      .filter(([, handler]) => liveHandlers.has(handler))
      .map(([name, handler]) => [name, liveHandlers.get(handler)]),
  );
}
