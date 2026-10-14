// A permanent dispatch marker prevents automatic duplicate transfers, including
// after Stripe's idempotency retention window. Unknown outcomes require review.
async function promotionTransfer({
  db,
  ref,
  stripe,
  fieldValue,
  amount,
  destination,
  metadata,
  idempotencyKey,
  mode,
}) {
  const stamp = () => fieldValue.serverTimestamp();
  const claim = await db.runTransaction(async (tx) => {
    const s = await tx.get(ref),
      old = s.data();
    if (old) {
      if (
        old.amount !== amount ||
        old.destination !== destination ||
        old.mode !== mode
      )
        return { status: "needs_review", transferId: old.transferId ?? null };
      return { status: old.status, transferId: old.transferId ?? null };
    }
    tx.create(ref, {
      amount,
      destination,
      mode,
      status: "dispatching",
      createdAt: stamp(),
      updatedAt: stamp(),
    });
    return null;
  });
  if (claim)
    return {
      transferStatus:
        claim.status === "succeeded" ? "succeeded" : "needs_review",
      transferId: claim.transferId,
    };
  try {
    const transfer = await stripe.transfers.create(
      { amount, currency: "usd", destination, metadata },
      { idempotencyKey },
    );
    await ref.update({
      status: "succeeded",
      transferId: transfer.id,
      updatedAt: stamp(),
    });
    return { transferStatus: "succeeded", transferId: transfer.id };
  } catch (error) {
    await ref.update({
      status: "needs_review",
      issue: String(error.message ?? "Unconfirmed promotion transfer").slice(
        0,
        500,
      ),
      updatedAt: stamp(),
    });
    return { transferStatus: "needs_review", transferId: null };
  }
}
module.exports = { promotionTransfer };
