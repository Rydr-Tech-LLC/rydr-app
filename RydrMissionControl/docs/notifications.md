# Mission Control notifications

`/workspaces/live-beta/notifications` is admin-only. Notifications uses the existing central control database and push service, preserving registered devices and saved campaigns. Test-workspace access redirects to Live Beta and the API rejects Test-workspace delivery requests. The page supports Send now (queued for the next minute), scheduled announcements, a six-message Live Beta preset, cancellation, and delivery history. Existing iOS push registration is used; no iOS sources are changed by this feature.

## November 2026 beta

| Announcement | America/New_York | UTC | Audiences |
| --- | --- | --- | --- |
| Five days | October 27, 9 AM | 13:00Z | Rider and driver |
| Three days | October 29, 9 AM | 13:00Z | Rider and driver |
| Launch | November 1, 9 AM | 14:00Z | Rider: take your first ride; driver: go online |

The preset is idempotent: its six fixed document IDs are created only if absent. Existing completed or cancelled announcements are never reset. Preset creation does not enable ride service or change approval status.

## Backend

The `dispatchNotificationCampaigns` scheduled function polls every minute. Campaigns live in `notificationCampaigns` and are writable only through the authenticated Admin SDK (the default Firestore rules deny client access). Deploy the composite `status` / `sendAt` index from `firestore.indexes.json` before relying on delivery.

Each invocation processes up to ten campaigns, fifty accounts each. A six-minute lease prevents overlapping batches. Stable `messageId` values use the existing notification sender's inbox deduplication; cursor updates and counts are atomic. Cancellation wins over in-flight completion, but a batch already sending can finish. Announcements more than six hours late expire instead of delivering stale countdown copy. Deleted, disabled, suspended and rejected accounts are excluded. Enabled device tokens determine phone push eligibility. The shared sender records no-token, sent, partial and failed results. Provider acceptance does not prove delivery or reading. An unknown result after an interrupted attempt is not blindly resent, to avoid duplicate pushes.

A successful scheduler query updates `notificationSystem/scheduler.lastRunAt`. Mission Control warns if that heartbeat is absent or older than five minutes. Saving a campaign alone is not evidence the backend is active.

## Rollout and verification

1. Build Cloud Functions, then deploy only `functions:dispatchNotificationCampaigns` and `firestore:indexes` to the existing Firebase project. Do not deploy unrelated functions or security rules as part of this change.
2. Deploy the existing `rydr-app-missioncontrol` Vercel project (root directory `RydrMissionControl`).
3. Verify the heartbeat and create the beta preset from Notifications, or provision the same preset through the authenticated Admin SDK.
4. On an actual installed TestFlight rider and driver build, verify notification permission, a registered FCM token, and receipt of a targeted test notification before broad sends. Local Swift source alone does not prove the installed build has push enabled or that production APNs credentials work.

Checks: `npm run build` in Cloud Functions; `node --test test/notificationCampaigns.test.cjs test/notifications.test.cjs`; TypeScript checks in Mission Control; `node --test scripts/notificationCampaigns.test.cjs`.
