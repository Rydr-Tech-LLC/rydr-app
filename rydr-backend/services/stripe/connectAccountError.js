"use strict";
function connectAccountError(error) {
  const detail = String(error?.raw?.message || error?.message || "");
  if (/temporarily restricted your ability to create[\s\S]*connected account/i.test(detail)) {
    return { status: 503, body: { error: "connect_account_creation_restricted", message: "Payout setup is temporarily unavailable. Rydr support must resolve a Stripe account restriction. Please try again later." } };
  }
  return { status: 500, body: { error: "account_create_failed", message: "Payout setup could not be completed. Please try again, or contact Rydr support if this continues." } };
}
module.exports = { connectAccountError };
