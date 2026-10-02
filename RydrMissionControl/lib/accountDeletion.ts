import { FieldValue } from "firebase-admin/firestore";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { cleanupStripeAccount } from "@/lib/stripeCleanup";

export type AccountRole = "rider" | "driver";
export type AccountDeletionMode = "anonymize" | "hard";

function anonymizedFields(role: AccountRole) {
  const common = {
    firstName: "Deleted",
    lastName: "User",
    email: null,
    phoneNumber: null,
    phoneE164: null,
    deletedAt: FieldValue.serverTimestamp(),
    accountStatus: "removed",
    accountDeletionStatus: "completed"
  };
  if (role === "driver") {
    return {
      ...common,
      license: null,
      address: null,
      stripeAccountId: null,
      driverApprovalStatus: "rejected",
      isApproved: false,
      canGoOnline: false,
      online: false,
      isOnline: false,
      availabilityStatus: "offline"
    };
  }
  return common;
}

export async function deleteAccount({
  uid,
  adminUid,
  requestId,
  mode
}: {
  uid: string;
  adminUid: string;
  requestId: string;
  mode: AccountDeletionMode;
}) {
  const profileEntries = await Promise.all(
    (["rider", "driver"] as AccountRole[]).map(async (role) => {
      const ref = adminDb.collection(role === "driver" ? "drivers" : "riders").doc(uid);
      const snap = await ref.get();
      return { role, ref, snap, profile: snap.exists ? (snap.data() as Record<string, unknown>) : null };
    })
  );
  const existing = profileEntries.filter((entry) => entry.profile);
  if (existing.length === 0) throw new Error("Account profile not found");

  const stripe = await Promise.all(existing.map(async ({ role, profile }) => ({
    role,
    result: await cleanupStripeAccount(role, profile ?? {}, adminUid, requestId, uid)
  })));

  await adminAuth.deleteUser(uid).catch((err: { code?: string }) => {
    if (err?.code !== "auth/user-not-found") throw err;
  });

  for (const { role, ref, profile } of existing) {
    const phone = (profile?.phoneE164 ?? profile?.phoneNumber) as string | undefined;
    if (phone) {
      const indexRef = adminDb.collection(role === "driver" ? "driverPhoneIndex" : "riderPhoneIndex").doc(phone);
      const indexSnap = await indexRef.get();
      if (indexSnap.exists && indexSnap.data()?.uid === uid) await indexRef.delete();
    }

    if (mode === "hard") {
      await adminDb.recursiveDelete(ref);
    } else {
      const tokensSnap = await ref.collection("notificationTokens").get();
      await Promise.all(tokensSnap.docs.map((doc) => doc.ref.set({ enabled: false }, { merge: true })));
      await ref.set(anonymizedFields(role), { merge: true });
    }
  }

  await Promise.all([
    adminDb.collection("driver_status").doc(uid).delete().catch(() => undefined),
    adminDb.collection("publicDriverProfiles").doc(uid).delete().catch(() => undefined)
  ]);

  return { roles: existing.map((entry) => entry.role), stripe };
}

export async function restoreRejectedDeletionRequest(
  uid: string,
  roles: AccountRole[],
  priorAccountStatuses?: Partial<Record<AccountRole, string | null>>
) {
  await Promise.all(roles.map(async (role) => {
    const ref = adminDb.collection(role === "driver" ? "drivers" : "riders").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) return;
    const priorStatus = priorAccountStatuses?.[role];
    await ref.set({
      accountStatus: priorStatus ?? FieldValue.delete(),
      accountDeletionStatus: "rejected",
      accountDeletionRequestedAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  }));
}
