const { workspaceServiceURL } = require("../../firebase/functions/src/services/workspacePolicy");
const { currentWorkspace } = require("./workspaceContext");
const BASE = () => workspaceServiceURL(process.env.RYDR_STRIPE_BACKEND_URL || "https://rydr-stripe-backend.onrender.com", currentWorkspace());
async function authorizeRideEstimate({ rideId, fetchImpl = globalThis.fetch }) {
  const token = process.env.RYDR_INTERNAL_SERVICE_TOKEN;
  if (!token) throw Object.assign(new Error("Payment authorization is not configured"), { statusCode: 503, details: { rideId } });
  let response;
  try {
    response = await fetchImpl(`${BASE()}/internal/rides/${encodeURIComponent(rideId)}/authorize`, {
      method: "POST", headers: { "Content-Type": "application/json", "x-rydr-internal-token": token },
      body: "{}", signal: AbortSignal.timeout(30000)
    });
  } catch { throw Object.assign(new Error("Card authorization could not be verified. Retry this booking."), { statusCode: 503, details: { rideId } }); }
  const body = await response.json();
  const messages = {
    card_authorization_failed: "Your card could not authorize the estimated fare. Update your payment method and retry.",
    card_declined: "Your card was declined. Choose another card and retry.",
    outstanding_ride_payment: "Pay your outstanding ride balance before requesting another ride.",
    no_payment_method_on_file: "Add a payment card before requesting your ride.",
    no_stripe_customer_on_file: "Add a payment card before requesting your ride."
  };
  if (!response.ok) throw Object.assign(new Error(messages[body.error] || body.error || "Card authorization failed"), {
    statusCode: response.status, details: { clientSecret: body.clientSecret || null, paymentIntentId: body.paymentIntentId || null, rideId }
  });
  if (body.status !== "authorized") throw Object.assign(new Error("Card authorization is required before dispatch"), { statusCode: 402 });
  return body;
}
module.exports = { authorizeRideEstimate };
