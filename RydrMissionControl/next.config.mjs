import path from "node:path";
import { fileURLToPath } from "node:url";
const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Keep Firebase Admin and workspace Firestore on the same Node SDK instance.
  // Bundled duplicates break FieldValue/ServerTimestampTransform serialization.
  serverExternalPackages: ["firebase-admin", "@google-cloud/firestore", "@google-cloud/storage", "google-auth-library"],
  outputFileTracingRoot: workspaceRoot,
  turbopack: {
    root: workspaceRoot
  },
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "firebasestorage.googleapis.com" },
      { protocol: "https", hostname: "storage.googleapis.com" }
    ]
  }
};

export default nextConfig;
