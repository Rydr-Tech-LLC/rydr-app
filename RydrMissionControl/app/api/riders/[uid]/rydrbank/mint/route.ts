import { randomInt } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import type { DocumentReference, Transaction } from "firebase-admin/firestore";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";

export const runtime = "nodejs";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const REWARD_GROUPS = ["go_eco", "xl", "prestine", "executive"] as const;

type RewardGroup = (typeof REWARD_GROUPS)[number];

function randomCode() {
  let value = "";
  for (let i = 0; i < 8; i += 1) {
    value += ALPHABET[randomInt(ALPHABET.length)];
  }
  return `RB-${value.slice(0, 4)}-${value.slice(4, 8)}`;
}

function rewardLabelForGroup(group: RewardGroup) {
  if (group === "xl") return "Rydr XL";
  if (group === "prestine") return "Rydr Prestine";
  if (group === "executive") return "Rydr Executive";
  return "Rydr Go / Rydr Eco";
}

async function reserveUniqueCode(
  transaction: Transaction
): Promise<{ code: string; indexRef: DocumentReference }> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const code = randomCode();
    const indexRef = adminDb.collection("codes_index").doc(code);
    const indexSnap = await transaction.get(indexRef);
    if (!indexSnap.exists) return { code, indexRef };
  }

  throw new Error("Could not reserve a unique RydrBank code.");
}

export async function POST(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => ({}))) as {
    rewardGroup?: RewardGroup;
    maxMiles?: number;
    reason?: string;
  };

  const rewardGroup = body.rewardGroup ?? "go_eco";
  if (!REWARD_GROUPS.includes(rewardGroup)) {
    return NextResponse.json({ error: "Invalid reward group." }, { status: 400 });
  }

  const maxMiles = Number.isFinite(body.maxMiles) ? Number(body.maxMiles) : 15;
  if (!Number.isInteger(maxMiles) || maxMiles < 1 || maxMiles > 100) {
    return NextResponse.json({ error: "Max miles must be a whole number from 1 to 100." }, { status: 400 });
  }

  try {
    const result = await adminDb.runTransaction(async (transaction) => {
      const riderRef = adminDb.collection("riders").doc(params.uid);
      const userRef = adminDb.collection("users").doc(params.uid);
      const [riderSnap, userSnap] = await Promise.all([
        transaction.get(riderRef),
        transaction.get(userRef)
      ]);

      if (!riderSnap.exists) {
        throw new Error("rider_not_found");
      }

      const { code, indexRef } = await reserveUniqueCode(transaction);
      const codeRef = userRef.collection("rydrBankCodes").doc();
      const rewardLabel = rewardLabelForGroup(rewardGroup);
      const now = FieldValue.serverTimestamp();

      if (!userSnap.exists) {
        transaction.set(userRef, {
          createdFromMissionControl: true,
          riderUid: params.uid,
          createdAt: now
        });
      }

      transaction.set(indexRef, {
        code,
        currentOwnerUid: params.uid,
        codeDocPath: codeRef.path,
        createdAt: now,
        rewardGroup,
        rewardLabel,
        maxMiles,
        status: "active",
        source: "mission_control"
      });

      transaction.set(codeRef, {
        code,
        status: "active",
        maxMiles,
        rewardGroup,
        rewardLabel,
        createdAt: now,
        reservedRideId: null,
        usedRideId: null,
        originalOwnerUid: params.uid,
        transferCount: 0,
        transferable: true,
        source: "mission_control",
        mintedBy: session.uid
      });

      transaction.set(
        userRef,
        {
          rydrBank: {
            codesAvailable: FieldValue.increment(1),
            codesEarned: FieldValue.increment(1)
          },
          updatedAt: now
        },
        { merge: true }
      );

      return { code, rewardGroup, rewardLabel, maxMiles };
    });

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: `RydrBank Code Minted (${result.code})`,
      targetType: "rider",
      targetId: params.uid,
      reason: body.reason
    });

    return NextResponse.json({ ok: true, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "server_error";
    if (message === "rider_not_found") {
      return NextResponse.json({ error: "Rider not found." }, { status: 404 });
    }

    console.error(error);
    return NextResponse.json({ error: "Could not mint RydrBank code." }, { status: 500 });
  }
}
