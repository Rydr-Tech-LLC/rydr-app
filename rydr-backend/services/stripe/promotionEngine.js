const { createHash } = require("node:crypto");
const policy = require("./promotionPolicy");
const { modeProfile } = require("./stripeMode");
const key = (...parts) =>
  createHash("sha256").update(JSON.stringify(parts)).digest("hex");
const number = (v) => (Number.isInteger(v) && v >= 0 ? v : 0);
const atCapacity = (p, total, user) =>
  (p.maxRedemptions != null && total >= p.maxRedemptions) ||
  (p.perUserLimit != null && user >= p.perUserLimit);

// All amounts and eligibility come from server-owned campaign and financial records.
// Reservations count against caps immediately and are reused on payment retries.
class PromotionEngine {
  constructor({ db, fieldValue, stripe, mode, now = () => Date.now() }) {
    Object.assign(this, { db, fieldValue, stripe, mode, now });
  }
  stamp() {
    return this.fieldValue.serverTimestamp();
  }
  async profile(uid, audience) {
    const s = await this.db
      .collection(audience === "drivers" ? "drivers" : "users")
      .doc(uid)
      .get();
    return s.data() ?? {};
  }
  async hasPriorPaidRide(uid, audience, excludeRideId, before = Infinity) {
    const snap = await this.db
      .collection("rides")
      .where(audience === "drivers" ? "driverId" : "riderId", "==", uid)
      .get();
    return snap.docs.some(
      (d) =>
        d.id !== excludeRideId &&
        d.data().status === "completed" &&
        d.data().paymentStatus === "succeeded" &&
        (policy.millis(d.data().completedAt) || 0) < before,
    );
  }
  async enroll(uid, rawCode, audience = "riders") {
    const code = policy.code(rawCode);
    if (!/^[A-Z0-9][A-Z0-9_-]{2,31}$/.test(code))
      throw new Error("Enter a valid promotion code.");
    const index = await this.db.collection("promotionCodes").doc(code).get();
    if (!index.exists) throw new Error("Promotion code not found.");
    const promotionId = index.data().promotionId;
    const ref = this.db.collection("promotions").doc(promotionId);
    const enrollment = this.db
      .collection("promotionEnrollments")
      .doc(key(promotionId, uid));
    const profile = await this.profile(uid, audience);
    if (audience === "drivers" && !profile.stripeAccountId)
      throw new Error(
        "Finish driver payout setup before joining this promotion.",
      );
    const prior = await this.hasPriorPaidRide(uid, audience);
    return this.db.runTransaction(async (tx) => {
      const [s, old, indexNow] = await Promise.all([
        tx.get(ref),
        tx.get(enrollment),
        tx.get(index.ref),
      ]);
      const p = s.data();
      if (
        !p ||
        p.schemaVersion !== 2 ||
        p.promoCode !== code ||
        indexNow.data()?.promotionId !== promotionId ||
        p.audience !== audience ||
        !["active", "scheduled"].includes(p.status) ||
        this.now() < policy.millis(p.startsAt) ||
        this.now() >= policy.millis(p.endsAt)
      )
        throw new Error("This code is not currently available.");
      if (
        !policy.audienceEligible(
          { ...p, applicationMode: "automatic" },
          uid,
          profile,
          prior ? 1 : 0,
          old.exists,
        )
      )
        throw new Error("This account is not eligible for this code.");
      if (!old.exists)
        tx.create(enrollment, {
          promotionId,
          userId: uid,
          audience,
          qualifiedAsNew: !prior,
          createdAt: this.stamp(),
        });
      return {
        promotionId,
        title: p.title,
        type: p.type,
        description: p.description ?? null,
        status: "enrolled",
      };
    });
  }
  async campaigns() {
    const s = await this.db
      .collection("promotions")
      .where("status", "in", ["active", "scheduled"])
      .get();
    return s.docs
      .filter((d) => d.data().schemaVersion === 2)
      .map((d) => ({ id: d.id, ...d.data() }));
  }
  async reserveRider({ rideId, ride, outcome, uid }) {
    const reservation = this.db
      .collection("rides")
      .doc(rideId)
      .collection("financial")
      .doc("promotion");
    const existing = await reservation.get();
    if (existing.exists)
      return existing.data().discountCents > 0 ? existing.data() : null;
    // Rydr Bank and cancellation discounts do not stack with fare promotions.
    if (
      number(outcome.promotionDiscountCents) > 0 ||
      outcome.outcomeType !== "completed"
    )
      return null;
    const [campaigns, rewards, profile, prior] = await Promise.all([
      this.campaigns(),
      this.db.collection("promotionRewards").where("userId", "==", uid).get(),
      this.profile(uid, "riders"),
      this.hasPriorPaidRide(uid, "riders", rideId),
    ]);
    const choices = campaigns
      .filter((p) => p.type === "rider_fare_discount")
      .map((p) => ({ promotion: p, rewardId: null }));
    for (const d of rewards.docs) {
      const r = d.data();
      if (
        r.status === "available" &&
        r.audience === "riders" &&
        policy.millis(r.expiresAt) > this.now()
      )
        choices.push({ promotion: r.offer, rewardId: d.id });
    }
    choices.forEach(
      (c) =>
        (c.discountCents = policy.discountCents(c.promotion, outcome, ride)),
    );
    choices.sort(
      (a, b) =>
        b.discountCents - a.discountCents ||
        a.promotion.id.localeCompare(b.promotion.id),
    );
    return this.db.runTransaction(async (tx) => {
      const old = await tx.get(reservation);
      if (old.exists) return old.data().discountCents > 0 ? old.data() : null;
      for (const choice of choices) {
        if (!choice.discountCents) continue;
        let p = choice.promotion;
        const rewardRef = choice.rewardId
          ? this.db.collection("promotionRewards").doc(choice.rewardId)
          : null;
        const promotionRef = this.db.collection("promotions").doc(p.id);
        const usageRef = this.db.collection("promotionUsage").doc(p.id);
        const userRef = this.db
          .collection("promotionProgress")
          .doc(key(p.id, uid));
        const enrollRef = this.db
          .collection("promotionEnrollments")
          .doc(key(p.id, uid));
        const [live, usage, user, enroll, reward] = await Promise.all([
          tx.get(promotionRef),
          tx.get(usageRef),
          tx.get(userRef),
          tx.get(enrollRef),
          rewardRef ? tx.get(rewardRef) : Promise.resolve(null),
        ]);
        if (rewardRef) {
          if (
            reward.data()?.status !== "available" ||
            policy.millis(reward.data().expiresAt) <= this.now()
          )
            continue;
          p = reward.data().offer;
        } else {
          p = { id: live.id, ...live.data() };
          if (p.schemaVersion !== 2 || p.type !== "rider_fare_discount")
            continue;
        }
        if (!policy.rideEligible(p, ride, this.now(), !!rewardRef)) continue;
        if (
          !rewardRef &&
          !policy.audienceEligible(
            p,
            uid,
            profile,
            prior ? 1 : 0,
            enroll.exists || user.data()?.qualifiedAsNew === true,
          )
        )
          continue;
        if (
          !rewardRef &&
          atCapacity(
            p,
            number(usage.data()?.issuedCount),
            number(user.data()?.issuedCount),
          )
        )
          continue;
        const discountCents = policy.discountCents(p, outcome, ride);
        if (!discountCents) continue;
        const result = {
          promotion: { ...p, id: p.id },
          promotionId: p.id,
          rewardId: choice.rewardId,
          discountCents,
          status: "reserved",
          userId: uid,
          rideId,
          createdAt: this.stamp(),
        };
        tx.create(reservation, result);
        if (rewardRef)
          tx.update(rewardRef, {
            status: "reserved",
            reservedRideId: rideId,
            updatedAt: this.stamp(),
          });
        else {
          tx.set(
            usageRef,
            {
              issuedCount: number(usage.data()?.issuedCount) + 1,
              updatedAt: this.stamp(),
            },
            { merge: true },
          );
          tx.set(
            userRef,
            {
              userId: uid,
              promotionId: p.id,
              audience: "riders",
              issuedCount: number(user.data()?.issuedCount) + 1,
              qualifiedAsNew: user.data()?.qualifiedAsNew === true || !prior,
              updatedAt: this.stamp(),
            },
            { merge: true },
          );
        }
        return result;
      }
      // Persist no-offer too: a retry must never change the Stripe idempotent amount.
      tx.create(reservation, {
        status: "none",
        discountCents: 0,
        rideId,
        userId: uid,
        createdAt: this.stamp(),
      });
      return null;
    });
  }
  async settle(rideId) {
    const rideRef = this.db.collection("rides").doc(rideId);
    const [rs, os, ps] = await Promise.all([
      rideRef.get(),
      rideRef.collection("financial").doc("outcome").get(),
      rideRef.collection("financial").doc("promotion").get(),
    ]);
    const ride = rs.data(),
      outcome = os.data();
    if (
      !ride ||
      ride.status !== "completed" ||
      ride.paymentStatus !== "succeeded" ||
      outcome?.status !== "paid" ||
      outcome.outcomeType !== "completed"
    )
      return { status: "not_eligible" };
    const reserved = ps.data();
    if (reserved?.discountCents > 0)
      await this.db.runTransaction(async (tx) => {
        const s = await tx.get(ps.ref);
        if (s.data()?.status === "applied") return;
        const ref = this.db
          .collection("promotionRedemptions")
          .doc(key(reserved.promotionId, rideId, ride.riderId));
        tx.set(ref, {
          promotionId: reserved.promotionId,
          promotionTitle: reserved.promotion.title,
          promotionType: reserved.promotion.type,
          rideId,
          riderId: ride.riderId,
          userId: ride.riderId,
          driverId: ride.driverId ?? null,
          discountCents: reserved.discountCents,
          status: "applied",
          createdAt: this.stamp(),
        });
        tx.update(ps.ref, { status: "applied", updatedAt: this.stamp() });
        if (reserved.rewardId)
          tx.update(
            this.db.collection("promotionRewards").doc(reserved.rewardId),
            { status: "used", usedRideId: rideId, updatedAt: this.stamp() },
          );
      });
    const all = await this.db
      .collection("promotions")
      .where("status", "in", ["active", "scheduled", "paused", "ended"])
      .get();
    const campaigns = all.docs
      .filter((d) => d.data().schemaVersion === 2)
      .map((d) => ({ id: d.id, ...d.data() }));
    const effectiveTime =
      policy.millis(ride.completedAt) ||
      policy.millis(outcome.finalizedAt) ||
      this.now();
    for (const original of campaigns) {
      if (
        original.status === "paused" &&
        effectiveTime >= policy.millis(original.pausedAt)
      )
        continue;
      const p = { ...original, status: "active" };
      if (
        !policy.rideEligible(p, ride, effectiveTime) ||
        p.type === "rider_fare_discount"
      )
        continue;
      const audience = p.audience,
        uid = audience === "drivers" ? ride.driverId : ride.riderId;
      if (!uid) continue;
      // A free/discounted reward ride cannot create a loop of free rider rewards.
      if (
        audience === "riders" &&
        (number(outcome.promotionDiscountCents) > 0 ||
          number(ride.backendPromotionDiscountCents) > 0 ||
          number(outcome.finalRiderChargeCents) === 0)
      )
        continue;
      const [profile, prior] = await Promise.all([
        this.profile(uid, audience),
        this.hasPriorPaidRide(uid, audience, rideId, effectiveTime),
      ]);
      await this.grantForRide(
        p,
        uid,
        rideId,
        ride,
        profile,
        prior,
        effectiveTime,
      );
    }
    const pending = await this.db
      .collection("promotionRedemptions")
      .where("rideId", "==", rideId)
      .get();
    for (const d of pending.docs)
      if (d.data().schemaVersion === 2 && d.data().status === "pending_payout")
        await this.payDriverBonus(d.ref);
    return { status: "settled" };
  }
  async grantForRide(
    candidate,
    uid,
    rideId,
    ride,
    profile,
    prior,
    effectiveTime,
  ) {
    const pRef = this.db.collection("promotions").doc(candidate.id),
      marker = this.db
        .collection("promotionEvents")
        .doc(key(candidate.id, uid, rideId));
    const progress = this.db
      .collection("promotionProgress")
      .doc(key(candidate.id, uid));
    const usage = this.db.collection("promotionUsage").doc(candidate.id),
      enrollment = this.db
        .collection("promotionEnrollments")
        .doc(key(candidate.id, uid));
    return this.db.runTransaction(async (tx) => {
      const [live, event, ps, us, es] = await Promise.all([
        tx.get(pRef),
        tx.get(marker),
        tx.get(progress),
        tx.get(usage),
        tx.get(enrollment),
      ]);
      if (event.exists) return;
      const p = { id: live.id, ...live.data() };
      if (p.status === "paused" && effectiveTime >= policy.millis(p.pausedAt))
        return;
      if (p.status === "ended" || p.status === "paused") p.status = "active";
      if (
        p.schemaVersion !== 2 ||
        !policy.rideEligible(p, ride, effectiveTime) ||
        !policy.audienceEligible(
          p,
          uid,
          profile,
          prior ? 1 : 0,
          es.exists || ps.data()?.qualifiedAsNew === true,
        )
      )
        return;
      const count = number(ps.data()?.eligibleRideCount) + 1,
        issued = number(ps.data()?.issuedCount),
        total = number(us.data()?.issuedCount);
      const perRide = p.type === "driver_per_ride_bonus";
      const threshold = perRide ? 1 : number(p.milestoneRideCount);
      const reached =
        threshold > 0 && (perRide || count >= threshold * (issued + 1));
      const grant = reached && !atCapacity(p, total, issued);
      tx.create(marker, {
        promotionId: p.id,
        userId: uid,
        rideId,
        createdAt: this.stamp(),
      });
      tx.set(
        progress,
        {
          promotionId: p.id,
          promotionTitle: p.title,
          userId: uid,
          audience: p.audience,
          eligibleRideCount: count,
          milestoneRideCount: threshold,
          issuedCount: issued + (grant ? 1 : 0),
          qualifiedAsNew: ps.data()?.qualifiedAsNew === true || !prior,
          updatedAt: this.stamp(),
        },
        { merge: true },
      );
      if (!grant) return;
      tx.set(
        usage,
        { issuedCount: total + 1, updatedAt: this.stamp() },
        { merge: true },
      );
      const rewardId = key(p.id, uid, perRide ? rideId : issued + 1);
      if (p.audience === "drivers")
        tx.create(this.db.collection("promotionRedemptions").doc(rewardId), {
          schemaVersion: 2,
          promotionId: p.id,
          promotionTitle: p.title,
          promotionType: p.type,
          userId: uid,
          driverId: uid,
          rideId,
          rewardKind: "cash_bonus",
          rewardCents: perRide ? p.bonusCents : p.rewardCents,
          status: "pending_payout",
          mode: this.mode,
          createdAt: this.stamp(),
        });
      else
        tx.create(this.db.collection("promotionRewards").doc(rewardId), {
          promotionId: p.id,
          promotionTitle: p.title,
          userId: uid,
          audience: "riders",
          offer: p,
          status: "available",
          expiresAt: new Date(this.now() + p.rewardExpiresAfterDays * 86400000),
          createdAt: this.stamp(),
        });
    });
  }
  async payDriverBonus(ref) {
    // The durable dispatch marker is written before calling Stripe. Ambiguous
    // failures require review rather than risking a second transfer after 24h.
    const reward = await this.db.runTransaction(async (tx) => {
      const s = await tx.get(ref),
        r = s.data();
      if (r?.status !== "pending_payout") return null;
      tx.update(ref, {
        status: "dispatching",
        dispatchStartedAt: this.stamp(),
      });
      return r;
    });
    if (!reward) return;
    try {
      if (reward.mode !== this.mode)
        throw new Error("Stripe mode mismatch; review bonus before payment.");
      const driver = modeProfile(
        await this.profile(reward.driverId, "drivers"),
        this.mode,
      );
      if (driver.stripeMode && driver.stripeMode !== this.mode)
        throw new Error("Driver Stripe mode does not match this bonus.");
      if (!driver.stripeAccountId || !driver.stripeChargesEnabled)
        throw new Error("Driver payout account is not ready.");
      const account = await this.stripe.accounts.retrieve(
        driver.stripeAccountId,
      );
      if (
        account.metadata?.uid !== reward.driverId ||
        account.details_submitted !== true
      )
        throw new Error("Driver payout ownership or setup needs review.");
      const transfer = await this.stripe.transfers.create(
        {
          amount: reward.rewardCents,
          currency: "usd",
          destination: driver.stripeAccountId,
          metadata: {
            promotionId: reward.promotionId,
            driverId: reward.driverId,
            rideId: reward.rideId,
            promotionRewardId: ref.id,
          },
        },
        { idempotencyKey: `promotion-bonus-${ref.id}` },
      );
      await ref.update({
        status: "paid",
        stripeTransferId: transfer.id,
        paidAt: this.stamp(),
        updatedAt: this.stamp(),
      });
    } catch (error) {
      await ref.update({
        status: "needs_review",
        issue: String(error.message ?? "Bonus payment needs review").slice(
          0,
          500,
        ),
        updatedAt: this.stamp(),
      });
    }
  }
  async accountSummary(uid, audience) {
    const [promos, progress, rewards, bonuses] = await Promise.all([
      this.campaigns(),
      this.db.collection("promotionProgress").where("userId", "==", uid).get(),
      this.db.collection("promotionRewards").where("userId", "==", uid).get(),
      this.db
        .collection("promotionRedemptions")
        .where("driverId", "==", uid)
        .get(),
    ]);
    const [profile, prior, enrollments] = await Promise.all([
      this.profile(uid, audience),
      this.hasPriorPaidRide(uid, audience),
      this.db
        .collection("promotionEnrollments")
        .where("userId", "==", uid)
        .get(),
    ]);
    const enrolled = new Set(enrollments.docs.map((d) => d.data().promotionId));
    return {
      bonuses:
        audience === "drivers"
          ? bonuses.docs
              .filter((d) => d.data().mode === this.mode)
              .map((d) => ({
                id: d.id,
                title: d.data().promotionTitle,
                status: d.data().status,
                rewardCents: d.data().rewardCents,
              }))
          : [],
      promotions: promos
        .filter(
          (p) =>
            p.audience === audience &&
            this.now() >= policy.millis(p.startsAt) &&
            this.now() < policy.millis(p.endsAt) &&
            policy.audienceEligible(
              p,
              uid,
              profile,
              prior ? 1 : 0,
              enrolled.has(p.id) ||
                progress.docs.some(
                  (d) =>
                    d.data().promotionId === p.id && d.data().qualifiedAsNew,
                ),
            ),
        )
        .map((p) => ({
          id: p.id,
          title: p.title,
          description: p.description ?? null,
          type: p.type,
          applicationMode: p.applicationMode,
          milestoneRideCount: p.milestoneRideCount ?? null,
          bonusCents: p.bonusCents ?? null,
          rewardCents: p.rewardCents ?? null,
          discountKind: p.discountKind ?? null,
          discountPercent: p.discountPercent ?? null,
          discountCents: p.discountCents ?? null,
          maxDiscountCents: p.maxDiscountCents ?? null,
          maxDistanceMiles: p.maxDistanceMiles ?? null,
          markets: p.markets ?? [],
          rideTypes: p.rideTypes ?? [],
          endsAt: new Date(policy.millis(p.endsAt)).toISOString(),
        })),
      progress: progress.docs.map((d) => ({ id: d.id, ...d.data() })),
      rewards: rewards.docs
        .filter(
          (d) =>
            d.data().audience === audience &&
            (d.data().status !== "available" ||
              policy.millis(d.data().expiresAt) > this.now()),
        )
        .map((d) => ({
          id: d.id,
          ...d.data(),
          expiresAt: new Date(policy.millis(d.data().expiresAt)).toISOString(),
        })),
    };
  }
}
module.exports = { PromotionEngine, key, atCapacity };
