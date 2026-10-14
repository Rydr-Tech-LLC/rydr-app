# Automatic vehicle imagery

No iOS release is required. The existing `getVehicleImage` / vehicle submission
calls still return the same payload and published images live in the same
Mission Control library. A missing exact color match queues a deduplicated
`vehicleImageJobs/{sha256}` document. Existing fallback images remain usable.

## Acquisition

A Firestore worker searches Wikimedia Commons for make/model/year/color,
retrieves at most six candidates, verifies source license metadata, downloads
bounded JPEG/PNG/WebP files from Wikimedia’s `upload.wikimedia.org` / `thumb.wikimedia.org` hosts without redirects,
and asks the OpenAI Responses API to assess them. Only a 0.95+ assessment
with every vehicle/year/trim/color/white-background/whole-car/no-watermark
check true is accepted. This score is a model assessment, not a calibrated
accuracy guarantee. Source metadata must support the year and requested trim;
pixels alone cannot verify them. Images are representative, not photos of the
driver's actual car. Commons coverage for exact trim/color studio images is
limited; many searches will require review.

Because existing clients lack attribution UI, auto-import only accepts public
domain or CC0 files without declared restrictions or attribution requirements.
All candidates preserve author/source/license metadata. No Google scraping,
image generation, recoloring, or uncertain-license publication is performed.
Additional licensed search sources can be added in `findCandidates` later.

Automatic publication uses a unique object path and a Firestore transaction;
it never overwrites an existing curated color slot. Provenance is stored in
`vehicleLibrary/{vehicleId}.imageSources.{color}`. Ingestion does not assign
ride eligibility. Failed or uncertain work becomes `needs_review`. The worker
is bounded to two concurrent instances, six candidates/job, and one search per
vehicle/year/trim/color, with a default global budget of 100 jobs per UTC day.
`VEHICLE_IMAGE_DAILY_LIMIT` can set that budget between 1 and 1000. Queuing failures do not fail signup. Dismissed jobs do
not automatically repeat. OpenAI/search failures are reviewable and retryable.

## Existing apps and records

A driver trigger registers missing-image/fallback-image records as waiters.
A 15-minute maintenance task scans existing drivers in pages of 100 using a
persistent cursor, and marks interrupted workers for review after 15 minutes.
Completed work updates matching driver records transactionally, checking the
current vehicle again and preserving existing exact/custom photos. It writes
both `vehicle.imageUrl` and `vehicle.imageURL`; the public-profile projection
reads both. Completed jobs can serve drivers that register later. Clients
refresh according to their existing Firestore/lookup behavior; an in-progress
signup preview won't automatically poll for a late image without an app change.

## Mission Control

Vehicle Library links to `/vehicle-library/review` and shows an unresolved issue
count. Admins can inspect candidate sources and reasons, retry, dismiss, or
upload a replacement using the existing library tools and choose “Use uploaded
library image.” The replacement must be in the exact year/trim entry and color
slot. Review actions use the existing admin session and audit log. No public
client has direct access to jobs or worker settings.

## Activation

1. Set the Firebase secret securely (do not paste a key into chat):
   `firebase functions:secrets:set OPENAI_API_KEY --project rydrapp-c7ec1`
2. Optionally configure `VEHICLE_IMAGE_MODEL` in the Functions environment.
   The default is `gpt-4.1-mini` with image input and strict structured output.
3. Build and deploy Functions from `rydr-backend/firebase`:
   `firebase deploy --only functions:onVehicleImageJobWritten,functions:onDriverVehicleImageNeeded,functions:maintainVehicleImageJobs,functions:getVehicleImage,functions:submitVehicleVin,functions:submitVehicleManual,functions:onDriverPublicProfileProjection --project rydrapp-c7ec1`
4. Deploy Mission Control using the existing hosting process.
5. Request an image for a supported color; verify a single job, then either a
   completed library image and driver URL or an issue in Mission Control.

OpenAI API billing, Cloud Functions/Scheduler, and Storage charges apply even
though Commons has no image subscription. Configure account budgets before
activation. No API calls are needed for the offline regression tests.

## Deployment status — October 14, 2026

The seven Functions listed above were deployed to `rydrapp-c7ec1`. The worker
uses enabled Secret Manager version 1 of `OPENAI_API_KEY`. A live API readiness
request returned `credit_balance_exhausted`; API credits must be added before
image evaluation can succeed. Credit/configuration failures stop evaluation
and become actionable review items. The live Range Rover search found six
Commons candidates, all CC BY-SA; they are review-only with the existing apps.

Mission Control production project: `khris-projects-7ab2c75b/rydr-app-missioncontrol`,
root directory `RydrMissionControl`, URL `https://rydr-app-missioncontrol.vercel.app`.
The review URL is `/vehicle-library/review`. Production is Git-linked to `main`;
CLI deployments publish local source independently of Git. Integrate the image automation branch into `main` before a future Git
deployment replaces the CLI-published version.

### Vercel authentication compatibility

The live deployment exposed `firebase-admin/auth` → `jwks-rsa` requiring the
ESM-only `jose` v6 under Vercel's disabled `require(esm)` runtime. Mission
Control overrides `jose` to 5.10.0 (CJS + ESM) with a matching locked tarball.
`scripts/authCompatibility.test.cjs` tests imports with ESM require disabled,
RSA JWKS conversion, valid signatures, tampered payload rejection, and invalid
keys. Preview login requests returned 200 and unauthenticated review actions
returned 401 after this correction.

Final Mission Control production deployment: `dpl_HjBSSE16nYNat8wA7gu3kK6YFfEu`
(`https://rydr-app-missioncontrol-k7m2uj7d3-khris-projects-7ab2c75b.vercel.app`).
The production-target build was checked before promotion to the existing
project domain. All 25 backend tests and both auth compatibility tests passed.
The live Range Rover job is `needs_review` with six candidates and zero
automatically permitted licenses; no image was imported for that sample.
