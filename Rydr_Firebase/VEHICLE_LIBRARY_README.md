# Rydr Vehicle Library System (Hybrid VIN Decoder + Mission Control)

Drivers never upload a photo of their actual vehicle. Instead they submit
their VIN (+ a chosen color), the backend decodes the VIN for free via the
NHTSA VIN Decoder API, and the platform displays a managed, generic
factory-style image of that make/model/year/color throughout the apps. This
document covers the schema, services, fallback logic, and how to operate the
system day to day.

## 1. Why this exists

- No per-driver vehicle photo to moderate, store, or worry about being
  inaccurate, outdated, or unusable for spoofing/fraud.
- Decoding is free (NHTSA's `vPIC` API, no API key, no rate-limit cost) and
  permanently cacheable, since a VIN's spec data never changes.
- One image asset serves every driver with the same make/model/year/trim/
  color combination — scales to thousands of drivers without thousands of
  uploads.
- The image-matching logic is provider-abstracted so a commercial vehicle
  image API (ChromeData, MarketCheck, J.D. Power, etc.) can be added later as
  a second `VehicleImageProvider` without any app-side changes.

## 2. Data model

### Firestore: `vehicleLibrary/{vehicleId}`

| Field | Type | Notes |
|---|---|---|
| `vehicleId` | string | Deterministic slug, e.g. `toyota_camry_2018_2024_le` |
| `make` | string | e.g. `Toyota` |
| `model` | string | e.g. `Camry` |
| `yearStart` / `yearEnd` | number | Inclusive generation range this entry covers |
| `trim` | string? | e.g. `LE`. Omit for a trim-agnostic entry |
| `bodyStyle` | string | One of `sedan`, `suv`, `truck`, `coupe`, `hatchback`, `van`, `minivan`, `wagon`, `convertible`, `crossover`, `unknown` |
| `availableColors` | string[] | Subset of the fixed 11-color list that has an uploaded image |
| `defaultImage` | string? | Storage path used when no color-specific image exists for this entry |
| `colorImages` | map<string, string> | Color name → Storage path |

Two reserved pseudo-make prefixes power the fallback chain (see §4) and are
never real manufacturers:

- `_generic_make_{make}` — a make-wide placeholder, e.g. `_generic_make_toyota`
- `_generic_body_{bodyStyle}` — a body-style-wide placeholder, e.g.
  `_generic_body_sedan`

### Firestore: `vinDecodeCache/{vin}`

Permanent cache of NHTSA's decode response, keyed by normalized (uppercase,
trimmed) VIN. Never expires — a VIN's factory specs don't change over time.
Locked down by Firestore rules (`allow read, write: if false`); only Cloud
Functions (via the Admin SDK) touch it.

### Firebase Storage: `vehicle-library/{Make}/{Model}/{Year}/{color}.webp`

Plus a `default.webp` per make/model/year for drivers whose color isn't
(yet) photographed. Images are public-read, write-locked (only Mission
Control's Admin SDK writes here).

## 3. Services

| Service | Where | Responsibility |
|---|---|---|
| `VehicleDecoderService` | `functions/src/services/vehicleDecoderService.ts` | Calls NHTSA `DecodeVinValuesExtended`, normalizes the response, permanently caches it in `vinDecodeCache` |
| `VehicleLibraryService` | `functions/src/services/vehicleLibraryService.ts` (Cloud Functions) and `RydrMissionControl/lib/vehicleLibrary.ts` (Mission Control, Admin-SDK direct) | CRUD over `vehicleLibrary` + Storage image upload/delete/search |
| `VehicleImageService` | `functions/src/services/vehicleImageService.ts` | Runs the 5-tier fallback chain through one or more `VehicleImageProvider`s, with a 10-minute in-memory cache |
| `VehicleImageProvider` | `functions/src/services/vehicleImageProvider.ts` | Interface for an image source. `FirebaseLibraryProvider` is the only implementation today. Future commercial providers (ChromeData, MarketCheck, J.D. Power) plug in here. |

## 4. Image fallback chain

`VehicleImageService.getImage()` asks each registered provider in order;
`FirebaseLibraryProvider` tries, in order, until one matches:

1. Exact `year + make + model + trim + color`
2. Exact `year + make + model` + the entry's `defaultImage` color
3. Nearest year within the same `vehicleLibrary` generation entry + default color
4. Generic make placeholder (`_generic_make_{make}`)
5. Generic body-style placeholder (`_generic_body_{bodyStyle}`)

If none of the five tiers find an uploaded image, the result has
`status: "missing"` (not an error) — clients render a local fallback icon
instead of a broken image link. This is intentional: the system is built
"empty" and Mission Control populates it over time; missing images are an
expected, handled state, not a bug.

## 5. Cloud Functions (callable, `Rydr_Firebase/functions`)

All three require a signed-in Firebase Auth user (driver or rider apps call
these with an ID token; Mission Control does not call these — it uses the
Admin SDK directly for all admin CRUD).

- **`decodeVin({ vin, forceRefresh? })`** → decoded vehicle fields (make,
  model, modelYear, trim, bodyStyle, driveType, fuelTypePrimary, …). Display
  only — does not write anything.
- **`getVehicleImage({ make, model, year, color, trim?, bodyStyle? })`** →
  `{ status, result }` per the fallback chain. Used for live color-picker
  previews before the driver commits.
- **`submitVehicleVin({ vin, color })`** → the single authoritative write.
  Re-decodes (cheap; cached) and re-matches the image server-side, then
  writes every resulting field onto `drivers/{uid}.vehicle` and
  `vinDecodeStatus`/`vehicleImageStatus` atomically via a merge-write. This
  is what the driver app's final "Continue" tap calls — never the client
  writing decoded fields directly — so the stored record is always
  self-consistent even if on-screen preview state ever drifted.

## 6. Driver app flow (RydrDriver)

`VehicleInfoView.swift` (signup step 5) + `VehicleLibraryClient.swift`
(`Core/`):

1. Driver types a 17-character VIN, taps **Decode Vehicle** →
   `VehicleLibraryClient.decodeVin` → summary shown (e.g. "2022 Toyota Camry
   LE").
2. Driver picks a color from the fixed 11-color grid → live preview via
   `VehicleLibraryClient.getVehicleImage`.
3. Driver fills in plate + uploads registration/insurance (unchanged from
   before) and taps Continue → `VehicleLibraryClient.submitVehicleVin`
   performs the authoritative server-side write.
4. `DriverSignupCoordinator.swift`'s `.vehicle` step then writes only the
   client-derived ride-type eligibility fields and the plate number, merged
   on top of what the Cloud Function already wrote (Firestore's nested
   `merge: true` makes this safe — see §8).

## 7. Rider app (RydrPlayground)

`DriverDashboardVM.publishPublicDriverProfile` (RydrDriver) mirrors
`vehicle.imageUrl`/`vehicle.color`/vehicle summary text onto
`publicDriverProfiles/{uid}` as `vehicleImageURL`, `vehicleColor`, and
`vehicleSummary`. `FirestoreRideService.swift` reads `vehicleImageURL`
(falling back to the legacy `carImage` field name) into the `Driver.carImage`
property, and `vehicleSummary` into `Driver.carMakeModel`.

`Core/VehicleImageView.swift`'s `VehicleOrDriverImage` view resolves an
image source as a bundled asset name first (legacy/local test data), then as
a remote URL (Vehicle Library images, served from Firebase Storage), and
otherwise renders the provided fallback. It's used in `DriverSelectionView`,
`DriverCardView`, and `RideInProgressView` so riders see the generic vehicle
image at every stage: matching, confirmation, and the active ride.

## 8. Mission Control (`RydrMissionControl`)

A new **Vehicle Library** nav section (`/vehicle-library`):

- Search/filter by make, model, year; flags for "missing images" and
  "incomplete color sets".
- `/vehicle-library/new` — create a library entry (including the
  `_generic_make_*` / `_generic_body_*` fallback entries).
- `/vehicle-library/{vehicleId}` — a 12-slot grid (default + 11 colors) to
  upload, replace, or delete images per color, with bulk-upload support.

The driver review page (`/drivers/{uid}`) shows decoded VIN, year, make,
model, trim, selected color, the generic vehicle image (or "Vehicle image
not yet available." with an **Add Vehicle Image →** quick link into the
Vehicle Library, pre-filtered to that make/model), VIN decode status, and
vehicle image status.

Mission Control talks to Firestore/Storage directly via the Admin SDK
(`lib/vehicleLibrary.ts`), not through the Cloud Functions — consistent with
every other privileged write Mission Control already performs. The Cloud
Functions exist for the mobile apps, which authenticate via Firebase Auth ID
tokens instead of Admin SDK credentials.

## 9. Firestore/Storage write-safety note

`drivers/{uid}.vehicle` is written from two places: the `submitVehicleVin`
Cloud Function (vin, make, model, trim, bodyStyle, driveType, fuelType,
color, imagePath, imageUrl, imageMatchTier) and the driver app client
(class, plate — and separately, registrationImageUrl/insuranceImageUrl via
the existing `upsertDriver` helper). This is safe because Firestore's
`set(data, { merge: true })` performs a **recursive** merge on nested map
fields — writing `vehicle.plate` does not erase `vehicle.make`, and vice
versa — rather than replacing the whole `vehicle` map.

## 10. Adding a future commercial image provider

1. Implement `VehicleImageProvider` (one method: `getImage(query)`) in
   `functions/src/services/`.
2. Register it via `vehicleImageService.addProvider(yourProvider, position?)`
   in `functions/src/index.ts` (or wherever the singleton is composed).
3. Nothing else changes — `getVehicleImage`/`submitVehicleVin`'s response
   shape, Mission Control, and both mobile apps are unaware of where an
   image came from.

## 11. Operating notes

- The fixed color list (`Black, White, Silver, Gray, Blue, Red, Green,
  Brown, Gold, Yellow, Orange`) is duplicated in three places by necessity —
  `functions/src/types.ts` (`VEHICLE_COLORS`), `RydrMissionControl/lib/
  vehicleLibrary.ts`, and `RydrDriver/RydrDriver/Core/VehicleLibraryClient.swift`
  (`VehicleColor`). Keep all three in sync if it ever changes.
- The system ships with an empty `vehicleLibrary` collection by design — no
  vehicle imagery is auto-generated or fabricated. Populate it via Mission
  Control's Vehicle Library pages as real images become available, starting
  with the highest-volume makes/models and the `_generic_body_*` placeholders
  (so the worst case is always "a generic sedan/SUV/truck", never a broken
  image).
