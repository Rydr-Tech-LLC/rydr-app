"use strict";
// The organization forbids new service-account keys. Existing external backends
// exchange their Google identity for narrowly scoped, short-lived Test access.
const TEST_PROJECT = "rydr-test-c7ec1";
const TEST_ACCOUNT = `rydr-test-backend@${TEST_PROJECT}.iam.gserviceaccount.com`;
const FEDERATION_AUDIENCE = "//iam.googleapis.com/projects/59820296181/locations/global/workloadIdentityPools/rydr-backends/providers/rydr-existing-backend";
const SOURCE_ACCOUNT = "firebase-adminsdk-fbsvc@rydrapp-c7ec1.iam.gserviceaccount.com";
const clients = new WeakMap();
function federatedTestCredential(source, load = (id) => require(id)) {
  if (source?.clientEmail !== SOURCE_ACCOUNT || !source.privateKey) return null;
  if (clients.has(source)) return clients.get(source);
  const {JWT, OAuth2Client, Impersonated, GoogleAuth} = load("google-auth-library");
  const identity = new JWT({email: source.clientEmail, key: source.privateKey});
  const external = new OAuth2Client();
  external.refreshHandler = async () => {
    const subjectToken = await identity.fetchIdToken(FEDERATION_AUDIENCE);
    const response = await fetch("https://sts.googleapis.com/v1/token", {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({grantType: "urn:ietf:params:oauth:grant-type:token-exchange",
        audience: FEDERATION_AUDIENCE,
        requestedTokenType: "urn:ietf:params:oauth:token-type:access_token",
        subjectTokenType: "urn:ietf:params:oauth:token-type:jwt", subjectToken,
        scope: "https://www.googleapis.com/auth/cloud-platform"}),
      signal: AbortSignal.timeout(15000),
    });
    const result = await response.json();
    if (!response.ok || !result.access_token) throw new Error("test_identity_exchange_failed");
    return {access_token: result.access_token, expiry_date: Date.now() + Number(result.expires_in) * 1000};
  };
  const authClient = new Impersonated({sourceClient: external, targetPrincipal: TEST_ACCOUNT,
    targetScopes: ["https://www.googleapis.com/auth/cloud-platform"], lifetime: 3600});
  const googleAuth = new GoogleAuth({authClient, projectId: TEST_PROJECT});
  const credential = {async getAccessToken() {
    const result = await authClient.getAccessToken();
    return {access_token: result.token, expires_in: Math.max(1, Math.floor((authClient.credentials.expiry_date - Date.now()) / 1000))};
  }};
  const value = {credential, googleAuth, authClient, serviceAccountId: TEST_ACCOUNT};
  clients.set(source, value);
  return value;
}
module.exports = {federatedTestCredential};
