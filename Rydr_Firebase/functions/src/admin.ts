import * as admin from "firebase-admin";

// Firebase CLI imports the Functions bundle during deploy to discover backend
// specs. Initializing Admin/Firestore at module load can block that discovery
// when local ADC/metadata lookup is slow, so initialize lazily inside the first
// real function invocation instead.
function app(): admin.app.App {
  return admin.apps.length > 0 ? admin.app() : admin.initializeApp();
}

function firestore(): admin.firestore.Firestore {
  return app().firestore();
}

function firebaseStorage(): admin.storage.Storage {
  return app().storage();
}

function firebaseMessaging(): admin.messaging.Messaging {
  return app().messaging();
}

export const db = new Proxy({} as admin.firestore.Firestore, {
  get(_target, prop, receiver) {
    const value = Reflect.get(firestore(), prop, receiver);
    return typeof value === "function" ? value.bind(firestore()) : value;
  }
});

export const storage = new Proxy({} as admin.storage.Storage, {
  get(_target, prop, receiver) {
    const value = Reflect.get(firebaseStorage(), prop, receiver);
    return typeof value === "function" ? value.bind(firebaseStorage()) : value;
  }
});

export const messaging = new Proxy({} as admin.messaging.Messaging, {
  get(_target, prop, receiver) {
    const value = Reflect.get(firebaseMessaging(), prop, receiver);
    return typeof value === "function" ? value.bind(firebaseMessaging()) : value;
  }
});

export const FieldValue = new Proxy({} as typeof admin.firestore.FieldValue, {
  get(_target, prop, receiver) {
    const value = Reflect.get(admin.firestore.FieldValue, prop, receiver);
    return typeof value === "function" ? value.bind(admin.firestore.FieldValue) : value;
  }
});

export const Timestamp = new Proxy({} as typeof admin.firestore.Timestamp, {
  get(_target, prop, receiver) {
    const value = Reflect.get(admin.firestore.Timestamp, prop, receiver);
    return typeof value === "function" ? value.bind(admin.firestore.Timestamp) : value;
  }
});
