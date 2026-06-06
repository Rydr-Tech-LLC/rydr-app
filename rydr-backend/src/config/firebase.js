const admin = require("firebase-admin");

let app;
let db;

function getCredential() {
  const { FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY } = process.env;

  if (FIREBASE_PROJECT_ID && FIREBASE_CLIENT_EMAIL && FIREBASE_PRIVATE_KEY) {
    return admin.credential.cert({
      projectId: FIREBASE_PROJECT_ID,
      clientEmail: FIREBASE_CLIENT_EMAIL,
      privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n")
    });
  }

  return admin.credential.applicationDefault();
}

function initializeFirebase() {
  if (app && db) {
    return { app, db };
  }

  if (admin.apps.length > 0) {
    app = admin.app();
    db = admin.firestore();
    return { app, db };
  }

  const options = {
    credential: getCredential()
  };

  if (process.env.FIREBASE_DATABASE_URL) {
    options.databaseURL = process.env.FIREBASE_DATABASE_URL;
  }

  app = admin.initializeApp(options);
  db = admin.firestore();

  return { app, db };
}

function getFirestore() {
  return initializeFirebase().db;
}

module.exports = {
  admin,
  initializeFirebase,
  getFirestore
};
