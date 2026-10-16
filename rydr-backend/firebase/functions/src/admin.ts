import {currentWorkspace} from "./services/workspaceRuntime";
import { getAuth } from "firebase-admin/auth";
import { App, getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Firestore, Timestamp, getFirestore } from "firebase-admin/firestore";
import { Messaging, getMessaging } from "firebase-admin/messaging";
import { Storage, getStorage } from "firebase-admin/storage";

// Firebase CLI imports the Functions bundle during deploy to discover backend
// specs. Initializing Admin/Firestore at module load can block that discovery
// when local ADC/metadata lookup is slow, so initialize lazily inside the first
// real function invocation instead.
function app(): App {
  // The Functions runtime/tooling can register a *named* Admin app. That does
  // not imply [DEFAULT] exists; getApp() would throw for every notification.
  return getApps().find((candidate) => candidate.name === "[DEFAULT]") ?? initializeApp();
}

function firestore(): Firestore {
  return getFirestore(app(),currentWorkspace()==="test"?"(default)":"live-beta");
}

function firebaseStorage(): Storage {
  return getStorage(app());
}

function firebaseMessaging(): Messaging {
  return getMessaging(app());
}

export const db = new Proxy({} as Firestore, {
  get(_target, prop, receiver) {
    const service = firestore();
    const value = Reflect.get(service, prop, service);
    return typeof value === "function" ? value.bind(service) : value;
  }
});

export const storage = new Proxy({} as Storage, {
  get(_target, prop, receiver) {
    const service = firebaseStorage();
    const value = Reflect.get(service, prop, service);
    return typeof value === "function" ? value.bind(service) : value;
  }
});

export const messaging = new Proxy({} as Messaging, {
  get(_target, prop, receiver) {
    const service = firebaseMessaging();
    const value = Reflect.get(service, prop, service);
    return typeof value === "function" ? value.bind(service) : value;
  }
});

export { FieldValue, Timestamp };

export function firebaseAuth() { return getAuth(app()); }
