// Usage: npm run set-admin -- someone@rydr-go.com [--revoke]
// Requires the same FIREBASE_ADMIN_* env vars as the app itself (loaded
// from .env.local in the project root via dotenv).
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { initializeApp } from "firebase-admin/app";
import { cert } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

function loadEnvLocal() {
  try {
    const content = readFileSync(resolve(process.cwd(), ".env.local"), "utf8");
    for (const line of content.split("\n")) {
      const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (match && !process.env[match[1]]) process.env[match[1]] = match[2];
    }
  } catch {
    // .env.local not found — assume env vars are already set (e.g. CI).
  }
}

async function main() {
  loadEnvLocal();
  const [email, flag] = process.argv.slice(2);
  if (!email) {
    console.error("Usage: npm run set-admin -- someone@rydr-go.com [--revoke]");
    process.exit(1);
  }

  const app = initializeApp({
    credential: cert({
      projectId: process.env.FIREBASE_ADMIN_PROJECT_ID,
      clientEmail: process.env.FIREBASE_ADMIN_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_ADMIN_PRIVATE_KEY?.replace(/\\n/g, "\n")
    })
  });
  const auth = getAuth(app);

  const user = await auth.getUserByEmail(email);
  const revoke = flag === "--revoke";
  await auth.setCustomUserClaims(user.uid, revoke ? {} : { role: "admin" });

  console.log(`${revoke ? "Revoked" : "Granted"} admin role for ${email} (uid: ${user.uid}).`);
  console.log("They must sign out and back in for the new claim to take effect.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
