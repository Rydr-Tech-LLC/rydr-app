"use strict";

const path = require("path");
const dotenv = require("dotenv");
const Stripe = require("stripe");

dotenv.config({ path: path.resolve(__dirname, "..", ".env") });
dotenv.config();

const accountIds = process.argv.slice(2).filter((arg) => arg !== "--live");
const allowLive = process.argv.includes("--live");

if (!process.env.STRIPE_SECRET_KEY) {
  console.error("Missing STRIPE_SECRET_KEY.");
  process.exit(1);
}

if (accountIds.length === 0) {
  console.error("Usage: node scripts/delete-connected-accounts.js acct_123 [acct_456]");
  process.exit(1);
}

const invalidIds = accountIds.filter((id) => !id.startsWith("acct_"));
if (invalidIds.length > 0) {
  console.error(`Invalid connected account id(s): ${invalidIds.join(", ")}`);
  process.exit(1);
}

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: "2024-06-20",
});

async function deleteAccount(accountId) {
  const account = await stripe.accounts.retrieve(accountId);
  if (account.deleted) {
    console.log(`${accountId}: already deleted`);
    return;
  }

  if (account.livemode && !allowLive) {
    throw new Error(`${accountId} is live-mode. Re-run with --live only if you intend to delete it.`);
  }

  const deleted = await stripe.accounts.del(accountId);
  console.log(`${accountId}: deleted=${deleted.deleted}`);
}

(async () => {
  for (const accountId of accountIds) {
    try {
      await deleteAccount(accountId);
    } catch (err) {
      console.error(`${accountId}: ${err.message}`);
      process.exitCode = 1;
    }
  }
})();
