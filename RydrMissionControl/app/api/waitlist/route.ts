import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { adminDb } from "@/lib/firebaseAdmin";
import { notificationService } from "@/src/services/notifications/NotificationService";

type WaitlistRole = "rider" | "driver";

interface WaitlistRequestBody {
  firstName?: unknown;
  lastName?: unknown;
  email?: unknown;
  phoneNumber?: unknown;
  role?: unknown;
  source?: unknown;
}

const DEFAULT_ALLOWED_ORIGINS = [
  "https://rydr-go.com",
  "https://www.rydr-go.com",
  "http://localhost:3000",
  "http://localhost:5173",
  "http://127.0.0.1:5500"
];

export async function OPTIONS(request: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(request)
  });
}

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as WaitlistRequestBody | null;
  if (!body) {
    return json(request, { error: "Invalid JSON body." }, 400);
  }

  const firstName = cleanText(body.firstName);
  const lastName = cleanText(body.lastName);
  const email = cleanEmail(body.email);
  const phoneNumber = cleanPhone(body.phoneNumber);
  const role = cleanRole(body.role);
  const source = cleanText(body.source) || "rydr-go.com";

  const missing = [
    !firstName ? "firstName" : "",
    !lastName ? "lastName" : "",
    !email ? "email" : "",
    !phoneNumber ? "phoneNumber" : "",
    !role ? "role" : ""
  ].filter(Boolean);

  if (missing.length > 0) {
    return json(request, { error: `Missing required fields: ${missing.join(", ")}` }, 400);
  }

  const waitlistRole = role as WaitlistRole;
  const waitlistRef = adminDb.collection("betaWaitlist");
  const existing = await waitlistRef
    .where("emailLower", "==", email)
    .where("role", "==", waitlistRole)
    .limit(1)
    .get();

  const payload = {
    firstName,
    lastName,
    email,
    emailLower: email,
    phoneNumber,
    role: waitlistRole,
    source,
    status: "pending",
    updatedAt: FieldValue.serverTimestamp()
  };

  let applicationId: string;
  let created = false;

  if (existing.empty) {
    const doc = await waitlistRef.add({
      ...payload,
      createdAt: FieldValue.serverTimestamp()
    });
    applicationId = doc.id;
    created = true;
  } else {
    const doc = existing.docs[0];
    applicationId = doc.id;
    await doc.ref.set(payload, { merge: true });
  }

  const emailResult = await notificationService.sendWaitlistConfirmation({
    to: email,
    firstName
  });

  await waitlistRef.doc(applicationId).set(
    {
      confirmationEmailStatus: emailResult.ok ? "sent" : "failed",
      confirmationEmailSentAt: emailResult.ok ? FieldValue.serverTimestamp() : null,
      confirmationEmailError: emailResult.ok ? FieldValue.delete() : emailResult.error,
      confirmationEmailProviderId: emailResult.providerMessageId ?? null
    },
    { merge: true }
  );

  const internalAlertResult = await notificationService.sendWaitlistInternalAlert({
    applicationId,
    firstName,
    lastName,
    email,
    phoneNumber,
    role: waitlistRole,
    source,
    created
  });

  await waitlistRef.doc(applicationId).set(
    {
      internalAlertEmailStatus: internalAlertResult.ok ? "sent" : "failed",
      internalAlertEmailSentAt: internalAlertResult.ok ? FieldValue.serverTimestamp() : null,
      internalAlertEmailError: internalAlertResult.ok ? FieldValue.delete() : internalAlertResult.error,
      internalAlertEmailProviderId: internalAlertResult.providerMessageId ?? null
    },
    { merge: true }
  );

  return json(request, { ok: true, applicationId, status: "pending", created }, created ? 201 : 200);
}

function json(request: NextRequest, data: Record<string, unknown>, status: number) {
  return NextResponse.json(data, {
    status,
    headers: corsHeaders(request)
  });
}

function corsHeaders(request: NextRequest): HeadersInit {
  const origin = request.headers.get("origin");
  const allowedOrigins = configuredOrigins();
  const allowOrigin = origin && allowedOrigins.includes(origin) ? origin : allowedOrigins[0];

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin"
  };
}

function configuredOrigins(): string[] {
  const configured = process.env.PUBLIC_SITE_ALLOWED_ORIGIN?.split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
  return configured && configured.length > 0 ? configured : DEFAULT_ALLOWED_ORIGINS;
}

function cleanText(value: unknown): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, 120) : "";
}

function cleanEmail(value: unknown): string {
  if (typeof value !== "string") return "";
  const email = value.trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email.slice(0, 254) : "";
}

function cleanPhone(value: unknown): string {
  if (typeof value !== "string") return "";
  const phone = value.trim().replace(/[^\d+().\-\s]/g, "");
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  return digits.length >= 10 ? `+${digits}`.slice(0, 32) : "";
}

function cleanRole(value: unknown): WaitlistRole | "" {
  return value === "rider" || value === "driver" ? value : "";
}
