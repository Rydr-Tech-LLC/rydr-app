# Rydr business Facebook and Instagram connection

Mission Control's verified production origin is `https://rydr-app-missioncontrol.vercel.app`.
Evidence: `Rydr_Website/index.html` waitlist endpoint and
`rydr-backend/firebase/docs/vehicle-image-automation.md` deployment record.
The production `/login` returned HTTP 200 with title Rydr Mission Control on October 27, 2026.
The Meta redirect allowlist has been configured for the exact Test and Live Beta callback
paths below. All nine META_ settings were saved in Vercel Production on October 27, 2026. The App Secret, encryption key, and webhook verification token use Secret storage. Vercel CLI authentication is complete. Production deployment dpl_CaS51jxmKczbWJsCaBQSPCNfRaVG was promoted to the live domain. Meta accepted the Live Beta webhook and its signed sample POST returned 200; invalid verification and unsigned POSTs returned 403 and 401. After admin reauthentication, the OAuth callback completed successfully and Mission Control displayed Connected for the Rydr Tech Page and @rydr_tech on October 27, 2026 at 4:02 p.m. Eastern. The reported token expiry is December 26, 2026 at 3:02 p.m. Eastern. The server validated the configured Page ID and linked Instagram username before saving the encrypted token. No real-asset webhook has been recorded; the successful Meta sample event was a transport/signature test only.

## Meta resources created

Update October 27, 2026: social workflows and redesigned screens are deployed in
`dpl_H22Ko1mrjykCcjB9GyBebrXTthmp`. The login configuration now includes
`pages_manage_metadata` and `pages_messaging`, both explicitly approved by Khris.
Reauthorization succeeded at 4:33 p.m. Eastern, with token expiry December 26 at
3:33 p.m. Eastern. Instagram analytics sync succeeded. The Instagram app-level
`messages` field and linked Page subscription are configured; the earlier code 200
permission error is resolved. The user-supplied https://www.rydr-go.com/privacy/ URL
was saved, and Meta confirmed successful publication. A real inbound "Hello Rydr"
was stored at 4:36 p.m. Eastern, and a user-authorized test reply was accepted by Meta
and recorded at 4:38 p.m. Rowen was paused again after that controlled run. Recipient-side
receipt and Advanced Access approval are not yet confirmed.

- App: Rydr Mission Control, ID `1747510056547573`, published October 27, 2026.
- Business portfolio: Rydr Tech LLC, ID `1459530352936702`.
- Login configuration: Rydr Facebook and Instagram, ID `1117275767350738`.
- Configuration requests Pages and Instagram accounts; system-user token, 60-day expiry.
- Enabled Instagram scopes: `instagram_basic`, `instagram_content_publish`,
  `instagram_manage_comments`, `instagram_manage_insights`, `instagram_manage_messages`.
- Page scopes: `pages_show_list`, `pages_read_engagement`, `pages_manage_metadata`,
  `pages_messaging`. Facebook publishing is not authorized. Mission Control currently
  implements Instagram replies only, although the token also has Page message access.
- Rydr Tech business Page asset ID observed in Business Dashboard inbox link:
  `1444445918742638`. Facebook's public profile URL uses `61595082909953`; this is not
  assumed to be the Graph Page ID. Verify against the authorized Graph response. If it
  differs, verify the selected business Page and set `META_FACEBOOK_PAGE_ID` accordingly.
- Instagram account: `rydr_tech`.

## Source implementation

Campus Growth → Social Connections is admin-only. Authorization is initiated by a
same-origin POST, with a random ten-minute state saved as a hash, bound to the current
admin and a Secure/HttpOnly/SameSite=Lax cookie. The callback atomically consumes state,
exchanges the code server-to-server, and requires the configured Page ID with its linked
Instagram username before saving any connection. Provider token responses never reach
the browser. Saved Page tokens use AES-256-GCM, bound to workspace and Page ID.

The webhook supports Meta's GET verification handshake and checks POST raw-body HMAC.
It records connection health and passes verified Instagram events to Rowen's inbox.
See `social-workflows.md` for message storage, eligible replies, scheduled Instagram
publishing, analytics, and the separate scheduler and campaign activation requirements.
Authorization alone does not start Rowen's social automation.

## Deployment checklist and remaining setup

1. Completed: set the server-only values documented in `.env.example`: `META_PUBLIC_ORIGIN`,
   `META_APP_ID`, `META_LOGIN_CONFIG_ID`, `META_GRAPH_VERSION`, `META_FACEBOOK_PAGE_ID`,
   `META_INSTAGRAM_USERNAME`, `META_APP_SECRET`, `META_TOKEN_ENCRYPTION_KEY`, and
   `META_WEBHOOK_VERIFY_TOKEN`. Use a 32-byte random encryption key encoded as hex and
   a separate random verification token. Keep the encryption key stable and out of Git.
2. Completed via CLI: deploy this source to the existing Vercel project `rydr-app-missioncontrol`. The
   current branch also contains the pending marketing agent work; review the full diff
   before publishing. Local tests do not prove a deployed OAuth round trip.
3. Completed: add exact Valid OAuth Redirect URIs in Facebook Login for Business → Settings:
   - `https://rydr-app-missioncontrol.vercel.app/api/meta/live-beta/callback`
   - `https://rydr-app-missioncontrol.vercel.app/api/meta/test/callback`
   Keep HTTPS and strict redirect matching enabled. No JavaScript SDK is required.
4. Completed: configure the Live Beta webhook after deployment:
   `https://rydr-app-missioncontrol.vercel.app/api/meta/live-beta/webhook`.
   Enter the server's verification token in Meta. Subscription fields and per-asset
   subscriptions need enabling when implementing the corresponding inbox/content features.
   A successful verification handshake alone does not mean an asset is subscribed.
5. Completed in Live Beta: sign into Mission Control as an admin, open Social Connections in Live Beta, and
   authorize only Rydr Tech's business Page and `rydr_tech`. Confirm the saved identities.
   For an owned-business test, the authorizing user must have the appropriate app role
   and business asset access. Meta may impose additional verification/review requirements.
6. Test callback replay/expiry, declined authorization, wrong-account rejection, token
   expiration, and a signed webhook round trip before building automated actions.
   Reconnection is required when a token expires or access is revoked. No refresh job is
   implemented. The displayed expiry is based on the authorization token's reported expiry;
   an absent expiry is shown as not recorded, not as proof of indefinite validity.

Test/Live Beta use isolated Firestore connections and workspace-specific callback paths.
OAuth state documents remain as small consumed/expired records; configure a retention job
or Firestore TTL before sustained use. Existing default-deny Firestore rules protect these
server-only collections. No raw inbound message content is retained by this module.

Validation: `node --test test/metaConnection.test.cjs`, `npx tsc --noEmit`, `npm run build`.
Official reference: https://developers.facebook.com/documentation/facebook-login/facebook-login-for-business
