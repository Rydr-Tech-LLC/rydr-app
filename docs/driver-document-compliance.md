# Driver document compliance and open-pilot screening

Executive remains disabled while funding is pending. These controls apply to the standard beta/pilot driver tiers and do not enable Executive.

## Document renewal

License, insurance and registration are monitored, plus vehicle inspection when one is recorded. Date-only documents remain current through the expiration day in America/New_York. Backend presence, matching, acceptance, scheduled pickup eligibility and Cash Hub access enforce compliance. An hourly Firebase job refreshes account state and retries undelivered compliance notifications; document and policy changes trigger immediate reconciliation.

Within 30 days, then within 7 days and 1 day, drivers receive a persisted inbox reminder and an FCM/APNs push. Expiration creates another notice. Upcoming document reminders are created between 9 a.m. and 6 p.m. Eastern; expiration notices are immediate. Notification IDs prevent ordinary repeated sends. Renewals supersede undelivered outdated reminders. Push requires an enabled registered device and notification permission; FCM acceptance is not evidence that a physical device displayed the alert.

Expired documents create a temporary driving hold. Sign-in, wallet, support and renewal uploads remain available. A verified current replacement removes only the compliance hold; safety/manual restrictions still apply. Drivers choose when to go online again. Pending or rejected uploads cannot clear an expired-document hold, and the last approved record remains authoritative while a replacement is reviewed. Upload generation checks prevent stale OCR results overwriting newer proof.

Mission Control shows dates, upcoming expirations, expired records and missing/unverified dates. Admins can verify a genuine uploaded document's date and driver/vehicle match. Unknown legacy dates need review rather than an invented deadline. Open-pilot screening enforcement additionally requires current verified dates for the three mandatory documents.

## Background screening transition

`platformConfig/driverCompliance.backgroundChecksRequired` remains false during beta. Mission Control Settings can require screening for the open pilot. The switch applies to all drivers, including previously approved beta drivers; beta deferrals and acknowledgements do not satisfy it. Turning it on recalculates holds and sends inbox/push notices.

For now, Mission Control records reviewed passing provider reports with a private reference, completion date, reviewer and requirement version (`open-pilot-v1`). Reports expire after 366 days; renewal notices and holds use that deadline. No automated provider ordering, continuous monitoring or adjudication integration is implemented. Select and configure a screening provider before enabling the pilot requirement; set a real `backgroundCheckURL` if using a hosted enrollment flow. Do not record SSNs or criminal-history contents in the reference field.

## Validation

Node policy/service tests cover Georgia midnight/DST, reminder stages, deduplication/retries, superseded pushes, preserved holds, reviewed report gating and out-of-order OCR. Firestore emulator tests cover protected fields and marketplace access. Simulator UI tests cover notification-to-Documents routing, displayed expiration dates, Documents return navigation and Wallet back navigation. Real-device push and provider screening E2E remain separate verification steps.
