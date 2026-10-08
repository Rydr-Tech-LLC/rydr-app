import { App, getApp, getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Firestore, Timestamp, getFirestore } from "firebase-admin/firestore";
import { Messaging, getMessaging } from "firebase-admin/messaging";
import { Storage, getStorage } from "firebase-admin/storage";

// Firebase CLI imports the Functions bundle during deploy to discover backend
// specs. Initializing Admin/Firestore at module load can block that discovery
// when local ADC/metadata lookup is slow, so initialize lazily inside the first
// real function invocation instead.
function app(): App {
  return getApps().length > 0 ? getApp() : initializeApp();
}

function firestore(): Firestore {
  return getFirestore(app());
}

function firebaseStorage(): Storage {
  return getStorage(app());
}

function firebaseMessaging(): Messaging {
  return getMessaging(app());
}

export const db = new Proxy({} as Firestore, {
  get(_target, prop, receiver) {
    const value = Reflect.get(firestore(), prop, receiver);
    return typeof value === "function" ? value.bind(firestore()) : value;
  }
});

export const storage = new Proxy({} as Storage, {
  get(_target, prop, receiver) {
    const value = Reflect.get(firebaseStorage(), prop, receiver);
    return typeof value === "function" ? value.bind(firebaseStorage()) : value;
  }
});

export const messaging = new Proxy({} as Messaging, {
  get(_target, prop, receiver) {
    const value = Reflect.get(firebaseMessaging(), prop, receiver);
    return typeof value === "function" ? value.bind(firebaseMessaging()) : value;
  }
});

export { FieldValue, Timestamp };
