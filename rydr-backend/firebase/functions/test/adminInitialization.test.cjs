const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApp, getApps, deleteApp } = require('firebase-admin/app');

test('lazy Admin services initialize DEFAULT even when a runtime named app exists', async () => {
  process.env.GCLOUD_PROJECT = 'demo-notifications';
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-notifications', storageBucket: 'demo-notifications.appspot.com' });
  const named = initializeApp({ projectId: 'demo-notifications' }, 'functions-runtime-test');
  assert.equal(getApps().length, 1);
  assert.throws(() => getApp(), /default Firebase app does not exist/);
  const { db, messaging, storage } = require('../lib/admin');
  assert.equal(db.collection('notifications').path, 'notifications');
  assert.equal(typeof messaging.sendEachForMulticast, 'function');
  assert.equal(typeof storage.bucket, 'function');
  assert.equal(getApp().name, '[DEFAULT]');
  assert.ok(getApps().some(app => app.name === "rydr-workspace-test"));
  assert.ok(getApps().some(app => app.name === "rydr-workspace-live-beta"));
  const initializedCount = getApps().length;
  // Repeated access reuses DEFAULT instead of initializing another app.
  db.collection('riders');
  assert.equal(getApps().length, initializedCount);
  await Promise.all(getApps().map(deleteApp));
});
