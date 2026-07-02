const { ImageAnnotatorClient } = require("@google-cloud/vision");

let client;

/**
 * Builds a Vision API client. Cloud Vision's annotation methods don't
 * enforce a separate fine-grained IAM role — any valid service-account
 * credential in a project that has the Vision API enabled can call them.
 * So rather than requiring a brand-new dedicated key, this reuses the
 * same Firebase Admin SDK credentials already configured for Firestore
 * (FIREBASE_ADMIN_PROJECT_ID / FIREBASE_ADMIN_CLIENT_EMAIL /
 * FIREBASE_ADMIN_PRIVATE_KEY, with legacy FIREBASE_* fallbacks).
 *
 * If you ever want a separate, narrower-scoped key for Vision only, set
 * GOOGLE_VISION_CREDENTIALS_JSON (full key file contents) and it'll be
 * used instead. Falls back to Application Default Credentials if neither
 * is set.
 */
function getVisionClient() {
  if (client) {
    return client;
  }

  const raw = process.env.GOOGLE_VISION_CREDENTIALS_JSON;

  if (raw) {
    let credentials;
    try {
      credentials = JSON.parse(raw);
    } catch (err) {
      throw new Error(
        "GOOGLE_VISION_CREDENTIALS_JSON is set but is not valid JSON. Make sure the full key file contents were pasted in as-is."
      );
    }

    client = new ImageAnnotatorClient({
      projectId: credentials.project_id,
      credentials: {
        client_email: credentials.client_email,
        private_key: credentials.private_key
      }
    });
    return client;
  }

  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID || process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL || process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY || process.env.FIREBASE_PRIVATE_KEY;

  if (projectId && clientEmail && privateKey) {
    client = new ImageAnnotatorClient({
      projectId,
      credentials: {
        client_email: clientEmail,
        private_key: privateKey.replace(/\\n/g, "\n")
      }
    });
    return client;
  }

  client = new ImageAnnotatorClient();
  return client;
}

module.exports = { getVisionClient };
