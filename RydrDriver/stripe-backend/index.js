"use strict";

/**
 * This nested Stripe backend is intentionally decommissioned.
 *
 * The only supported Stripe backend lives at ../../stripe-backend/index.js.
 * Keeping this legacy copy runnable would reintroduce unauthenticated
 * customer, PaymentIntent, Connect account, and payout endpoints.
 */
throw new Error(
  "RydrDriver/stripe-backend is decommissioned. Deploy the hardened root stripe-backend service instead."
);
