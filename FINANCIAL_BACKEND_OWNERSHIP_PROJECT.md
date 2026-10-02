# Project: Backend-Owned Financial Outcomes

Status: Ready to assign  
Suggested level: Junior software engineering student  
Primary codebase: `stripe-backend`  
Supporting codebases: Rider app, Driver app, Firebase rules, and Mission Control  
Project goal: A modified mobile client must never be able to choose how much a rider pays, how much a driver earns, or how much Rydr keeps.

## The assignment in one paragraph

Move every trusted financial decision for a standard card ride from the Rider and Driver apps into the backend. The apps may display estimates and send facts such as locations or a request to cancel, but they must not write a fare, fee, discount, payout, or payment result. The backend must calculate those values in integer cents, save an auditable financial outcome, and use only that saved outcome when creating Stripe charges or transfers.

## Why this work is needed

The current Stripe backend does some important things correctly: it authenticates the rider, loads the ride from Firestore, and does not blindly use the payment amount sent by the app. However, some of the Firestore fields it treats as authoritative are still calculated or written by a phone.

Examples found in the current code:

- The Rider app calculates initial fare components, wait charges, cancellation fees, and prorated cancellation values.
- The Driver app calculates final fare and mid-ride cancellation payout values.
- Firestore rules currently allow ride participants to write some financial fields.
- The Stripe backend reads fields such as `estimatedDriverPayoutCents`, `cancellationTotalChargeCents`, and `proratedCancellationChargeCents` when deciding the charge and payout.

That means a modified app could potentially influence a real financial result without directly changing the Stripe request amount. This project removes that path.

## Scope

### Included

- Upfront ride quote
- Minimum fare adjustment
- Booking fee
- Distance and time charges
- Paid pickup wait charge
- Rider cancellation fee
- Mid-ride cancellation proration
- Promotion or RydrBank discount
- Final rider charge
- Driver payout
- Rydr platform share
- Stripe PaymentIntent and transfer inputs
- Refund and manual adjustment records
- Financial receipt and immutable ledger entry
- Idempotency, authorization, audit history, tests, and Firestore rule changes
- Rider and Driver app migration away from writing financial fields

### Not included

- Cash Rydr Hub
- Driver matching and dispatch
- The complete ride lifecycle state-machine migration
- Rating or reputation changes
- Stripe Connect onboarding UI
- A new pricing policy or new fee amounts
- A Mission Control redesign

This project may add the minimum backend commands needed to capture trusted timing and distance evidence. It should not redesign unrelated ride behavior.

## Safety boundary for a student project

The student works against emulators, test accounts, and Stripe test mode. A mentor owns:

- Approval of the actual pricing rules and percentages
- Mapping-provider selection and API credentials
- Firebase and Stripe production secrets
- Production deployment and rollback approval
- Any production refund, transfer, or data migration
- Final review of Firestore security rules

The student must never copy production customer data into local fixtures.

## Definition of done

The project is complete only when all of the following are true:

- No Rider or Driver request contains a trusted fare, fee, discount, platform-share, or payout value.
- No Rider or Driver client can write protected financial fields to a ride.
- The backend calculates all money in integer cents using one versioned pricing module.
- Every completed or chargeable cancelled ride has one immutable financial outcome.
- Stripe uses that outcome—not legacy ride fields—to determine charges and transfers.
- Duplicate finalization or payment requests cannot create duplicate outcomes, charges, payouts, discounts, or refunds.
- Receipts shown by both apps come from the backend outcome.
- Unauthorized and tampered requests fail in automated tests.
- Existing valid ride scenarios produce expected results in shadow comparison.
- A mentor has reviewed the test-mode demonstration and security-rule changes.

## Backend ownership contract

### The client may send

- `rideId`
- A command such as quote, cancel, finalize, pay, or refund request
- Pickup and destination coordinates for a quote
- GPS or route telemetry as evidence
- A payment-method identifier owned by the authenticated rider
- A promotion code to validate
- A unique request ID for retry safety
- A user-authored cancellation or dispute reason

### The client must not decide or write

- Any amount in cents or dollars
- Distance/time charge
- Minimum fare adjustment
- Booking or cancellation fee
- Paid wait duration or wait charge
- Proration percentage or amount
- Promotion value
- Final rider charge
- Driver payout or platform share
- Payment, transfer, refund, or settlement status
- Stripe customer, destination account, or transfer amount

### The backend must derive

- Caller identity from the verified Firebase token
- Rider and driver identity from the canonical ride
- Rates from a server-owned pricing configuration and accepted driver-rate snapshot
- Quote distance and duration from a trusted server-side route result
- Final distance and time from trusted ride evidence
- Wait duration from server timestamps
- Cancellation eligibility from server timestamps and ride state
- Promotion eligibility from server records
- Stripe customer and Connect account from server records
- Every final amount from the versioned pricing module

## Required financial outcome

Create one backend-owned record for each chargeable ride, for example:

`rides/{rideId}/financial/outcome`

Minimum fields:

```text
rideId
pricingVersion
currency
outcomeType: completed | rider_cancellation | mid_ride_cancellation
distanceChargeCents
timeChargeCents
minimumFareAdjustmentCents
bookingFeeCents
waitChargeCents
cancellationFeeCents
grossChargeCents
promotionDiscountCents
finalRiderChargeCents
driverPayoutCents
platformShareCents
calculationInputs
calculationReason
calculatedAt
calculatedBy
status: finalized | paid | refunded | adjusted
paymentIntentId
transferIds
refundIds
createdAt
updatedAt
```

Use integer cents. Do not store `Double` values as the source of truth. Display-only dollar values may be derived from cents.

The record must satisfy:

```text
finalRiderChargeCents = max(0, grossChargeCents - promotionDiscountCents)
driverPayoutCents >= 0
platformShareCents >= 0
driverPayoutCents + platformShareCents equals the applicable ride economics
```

The exact handling of promotion subsidies must be documented and covered by tests.

## Suggested code structure

Keep new financial logic out of the 2,000-line `stripe-backend/index.js` where practical:

```text
stripe-backend/
  src/
    financial/
      money.js
      pricing-config.js
      calculate-quote.js
      calculate-final-outcome.js
      calculate-cancellation.js
      promotions.js
      financial-repository.js
      financial-service.js
  test/
    financial/
```

`index.js` should authenticate and route requests into these modules. Calculation modules should be pure functions whenever possible so they can be tested without Firebase or Stripe.

## Start-to-finish work plan

### Phase 0 — Learn the flow and establish a baseline

Tasks:

- [ ] Run the Rider app, Driver app, Firebase emulators, and Stripe backend locally.
- [ ] Complete one test ride and record which documents and fields change.
- [ ] Trace the code from quote to completion to PaymentIntent creation.
- [ ] List every client-written financial field in Rider, Driver, and Firestore rules.
- [ ] Add a short data-flow diagram to the pull request description.
- [ ] Confirm all Stripe work uses test mode.

Files to begin with:

- `Features/Booking/RideManager.swift`
- `Features/Booking/FirestoreRideService.swift`
- `RydrDriver/RydrDriver/Features/Dashboard/DriverDashboardVM.swift`
- `stripe-backend/index.js`
- `Rydr_Firebase/firestore.rules`

Checkpoint: The student can explain why “Stripe ignores the client amount” is not sufficient if Stripe trusts a client-written Firestore fare.

### Phase 1 — Write the financial contract and tests first

Tasks:

- [ ] Document all pricing inputs, formulas, rounding rules, and output fields.
- [ ] Assign a pricing version, such as `standard_usd_v1`.
- [ ] Define how rates are snapped at quote/acceptance time so later driver changes cannot alter a ride.
- [ ] Create table-driven test fixtures with inputs and expected cents.
- [ ] Add a real test runner to `stripe-backend`; syntax checking alone is not sufficient.

Required fixtures:

- [ ] Short ride that triggers the minimum fare
- [ ] Ride below and above the five-mile booking-fee boundary
- [ ] Each supported ride tier
- [ ] Minimum and maximum allowed driver rates
- [ ] Rounding at half-cent boundaries
- [ ] Complimentary wait only
- [ ] Paid wait with partial minutes
- [ ] Cancellation with no fee
- [ ] Cancellation with a fee
- [ ] Mid-ride cancellation near the lower and upper proration bounds
- [ ] Partial promotion and fully discounted ride
- [ ] Malformed, negative, missing, and extremely large inputs

Checkpoint: A mentor approves the written formulas and expected fixture values before endpoint work begins.

### Phase 2 — Build a pure, versioned pricing module

Tasks:

- [ ] Add safe integer-cent helpers and reject unsafe or negative values.
- [ ] Move tier minimums, booking fees, allowed rates, and platform share into backend configuration.
- [ ] Implement quote calculation as a pure function.
- [ ] Implement wait calculation as a pure function.
- [ ] Implement cancellation and proration calculations as pure functions.
- [ ] Implement driver payout and platform-share calculations as pure functions.
- [ ] Return a detailed breakdown plus `pricingVersion`.
- [ ] Make all Phase 1 fixtures pass.

Checkpoint: The calculation module imports neither Firebase nor Stripe and has deterministic tests.

### Phase 3 — Add backend quote creation

Tasks:

- [ ] Add an authenticated quote endpoint.
- [ ] Validate coordinates, ride type, selected driver, and request size.
- [ ] Obtain distance/duration from an approved server-side routing provider or trusted backend adapter.
- [ ] Load and clamp driver rates on the server.
- [ ] Validate a promotion code without trusting a client discount.
- [ ] Save the immutable quote inputs, rate snapshot, calculation, expiration, and pricing version.
- [ ] Return the display breakdown to the Rider app.
- [ ] Update the Rider app to display the server quote.

Acceptance tests:

- Another rider cannot read or use the quote.
- Changing an amount in the HTTP body has no effect because amount fields are rejected.
- An expired quote cannot start a ride.
- Changing driver rates after quote creation does not change that quote.

### Phase 4 — Capture trusted ride evidence

Financial calculations require trustworthy timing and distance facts.

Tasks:

- [ ] Record pickup arrival, paid-wait start, ride start, cancel, and completion times using server timestamps.
- [ ] Store append-only telemetry samples or a trusted route summary for final distance.
- [ ] Reject impossible ordering, such as completion before ride start.
- [ ] Reject stale, duplicate, or unauthorized events.
- [ ] Document fallback behavior when telemetry is missing.
- [ ] Never accept `waitChargeCents`, `fare`, `progress`, or `proratedChargeCents` as evidence.

Checkpoint: A client may report an event, but the backend decides whether it is valid and records the authoritative timestamp.

### Phase 5 — Finalize exactly one financial outcome

Tasks:

- [ ] Add one idempotent finalization command for completion and chargeable cancellation.
- [ ] Authenticate the participant and load the canonical ride, quote, rates, timestamps, and telemetry.
- [ ] Calculate the completed fare, wait charge, cancellation outcome, or proration on the backend.
- [ ] Apply promotions transactionally so one reward cannot be spent twice.
- [ ] Calculate driver payout and platform share.
- [ ] Write the financial outcome and immutable ledger entries in a transaction.
- [ ] Return the same outcome on a duplicate request.
- [ ] Reject attempts to finalize a non-chargeable state.

Required concurrency test:

Send the same finalization request 20 times at once. Exactly one outcome and one set of ledger entries may exist.

### Phase 6 — Make Stripe consume only the outcome

Tasks:

- [ ] Change ride charging to require a finalized financial outcome.
- [ ] Use `finalRiderChargeCents` for the PaymentIntent.
- [ ] Use backend-derived rider customer and driver Connect account IDs.
- [ ] Use `driverPayoutCents` and `platformShareCents` for transfer/application-fee behavior.
- [ ] Use a deterministic Stripe idempotency key based on ride and operation.
- [ ] Record Stripe IDs and statuses without rewriting the calculated breakdown.
- [ ] Process webhook events idempotently.
- [ ] Make zero-dollar promotions succeed without creating a zero-dollar PaymentIntent.
- [ ] Record refunds and adjustments as new ledger events; never silently edit the original outcome.

Failure tests:

- Timeout after Stripe succeeds but before Firestore updates
- Duplicate webhook delivery
- Duplicate payment button tap
- Payment requiring authentication
- Declined payment followed by retry
- Missing or disabled Connect account
- Promotion subsidy transfer failure
- Refund retry

Checkpoint: Searching Stripe payment code must show no fallback to legacy client-written financial fields.

### Phase 7 — Migrate both apps to display-only financial behavior

Rider app tasks:

- [ ] Replace local authoritative quote creation with the quote endpoint.
- [ ] Stop sending cancellation and proration amounts.
- [ ] Stop calculating paid wait as a trusted charge.
- [ ] Stop sending a payment amount.
- [ ] Render the final backend receipt.
- [ ] Keep local calculations only as explicitly labeled previews, if still needed for UI responsiveness.

Driver app tasks:

- [ ] Stop writing `fare` at completion.
- [ ] Stop writing cancellation charge, payout, platform fee, or progress values.
- [ ] Display estimated and finalized payout from backend records.
- [ ] Handle pending finalization and payment states without inventing an amount.

Checkpoint: A repository search finds no mobile write of a protected financial field.

### Phase 8 — Lock Firestore and prove the boundary

Tasks:

- [ ] Define the complete protected financial-field list in one reusable rules helper.
- [ ] Deny client creation or updates of those fields on `rides` and `rideRequests`.
- [ ] Deny all client writes to financial outcomes and ledger entries.
- [ ] Permit participants to read only the financial data appropriate to them.
- [ ] Add Firestore emulator tests for Rider, Driver, another user, unauthenticated user, and Admin SDK behavior.

Required tamper tests:

- Rider tries to set final charge to one cent.
- Rider tries to remove a cancellation fee.
- Driver tries to increase payout.
- Driver tries to shorten paid wait.
- Either client tries to mark a payment or refund successful.
- Another user tries to read or change the outcome.

All must fail before production rollout.

### Phase 9 — Shadow, document, and hand off

Tasks:

- [ ] Run old and new calculations side by side in staging without double charging.
- [ ] Log differences by formula component and pricing version.
- [ ] Investigate every unexplained difference greater than one cent.
- [ ] Add structured logs for quote, finalization, payment, transfer, webhook, and refund events.
- [ ] Add a Mission Control read view or document the existing inspection path.
- [ ] Write a rollback plan that preserves completed financial outcomes.
- [ ] Update backend API and operational documentation.
- [ ] Demonstrate the complete flow in Stripe test mode.

Final demonstration:

1. Create and display a backend quote.
2. Complete a normal ride and show its backend outcome and Stripe test payment.
3. Complete a paid-wait scenario.
4. Complete a chargeable cancellation.
5. Complete a promoted or free ride.
6. Retry finalization and payment to prove no duplicate money movement.
7. Attempt a direct Firestore tamper and show that rules reject it.

## Pull request sequence

Keep reviews small. Do not submit the entire project as one pull request.

1. **PR 1 — Contract and test harness:** Documentation, fixtures, and test runner.
2. **PR 2 — Pricing module:** Pure calculations and unit tests.
3. **PR 3 — Quote API:** Server quote persistence and Rider display integration.
4. **PR 4 — Trusted evidence:** Server timestamps and telemetry validation.
5. **PR 5 — Financial finalization:** Outcome, ledger, promotion consumption, and concurrency tests.
6. **PR 6 — Stripe integration:** Payment, transfer, webhook, refund, and failure tests.
7. **PR 7 — Mobile cleanup:** Remove Rider and Driver financial writes.
8. **PR 8 — Rules and rollout:** Emulator tests, protected fields, shadow comparison, and documentation.

Every PR must include:

- What changed and why
- Screenshots or sample request/response when relevant
- Tests run and results
- Security or data-migration impact
- Rollback behavior
- Remaining legacy paths

## Student check-in schedule

- End of Phase 0: explain the current trust gap.
- End of Phase 1: pricing-policy and fixture review.
- End of Phase 3: quote API demonstration.
- End of Phase 5: concurrency and idempotency demonstration.
- End of Phase 6: Stripe test-mode failure demonstration.
- End of Phase 8: security-rule tamper demonstration.
- End of Phase 9: final walkthrough and documentation handoff.

Stop and ask the mentor if a pricing rule is ambiguous. The student should implement approved policy, not invent financial policy.

## Discord-ready posts

Post each block as a separate message.

### Discord post 1 — Project assignment

**PROJECT: Backend-Owned Financial Outcomes**

**Goal:** A modified Rider or Driver app must never be able to choose how much a rider pays, how much a driver earns, or how much Rydr keeps.

You will move standard card-ride financial decisions into the backend. This includes quotes, minimum fares, booking fees, paid wait, cancellations, proration, promotions, final charges, driver payouts, platform share, refunds, and receipts.

The apps may display backend values and send ride events. They may not write trusted money values.

Work only with Firebase emulators, test accounts, and Stripe test mode. Production secrets, deployment, and financial-policy decisions stay with the mentor.

### Discord post 2 — Current problem

**Why this project exists**

Stripe currently ignores a client-supplied payment amount and reloads the ride from Firestore. That is helpful, but some Firestore fare and payout fields are still calculated or written by the Rider or Driver phone.

Examples include initial fare components, cancellation amounts, wait charges, prorated cancellation values, final fare, and driver payout.

So the real requirement is not only “do the Stripe call on the backend.” The backend must also own the calculation and the Firestore fields Stripe trusts.

### Discord post 3 — What you will build

**You will build:**

1. A versioned, integer-cent pricing module
2. Table-driven unit tests for every fare scenario
3. An authenticated backend quote endpoint
4. Trusted server timestamps and ride evidence
5. One idempotent financial-finalization command
6. An immutable financial outcome and ledger
7. Stripe charge, transfer, webhook, and refund handling based only on that outcome
8. Rider and Driver changes that remove financial writes
9. Firestore rules and emulator tests that reject tampering
10. A staging shadow comparison and test-mode demonstration

Cash Rydr Hub, dispatch, ratings, and a full ride-state migration are outside this project.

### Discord post 4 — Required rule

**The rule for every endpoint**

The client may send intent and evidence: `rideId`, command, coordinates, telemetry, payment-method selection, promotion code, and request ID. User identity must come from the verified Firebase token.

The client must never decide or write an amount, fee, discount, wait charge, proration, payout, platform share, payment status, transfer status, or refund status.

The backend verifies Firebase identity, loads the ride and accounts, validates the event, calculates in integer cents, saves an auditable outcome, and then calls Stripe.

### Discord post 5 — Work order

**Work in this order:**

1. Trace and document the current flow
2. Get pricing formulas approved
3. Add test fixtures and a real test runner
4. Build pure pricing functions
5. Build and integrate the quote API
6. Capture trusted timing/distance evidence
7. Finalize one transactional financial outcome
8. Make Stripe use only that outcome
9. Remove financial writes from both apps
10. Lock Firestore rules
11. Shadow-test old vs. new results
12. Demo normal, wait, cancellation, promotion, retry, and tamper scenarios

Submit the work as small PRs. Do not combine the whole project into one PR.

### Discord post 6 — Completion checklist

**Done means:**

- All trusted money is calculated by one versioned backend module
- Both apps send no trusted financial values
- Stripe has no fallback to client-written financial fields
- Every chargeable ride has one immutable outcome
- Duplicate requests create no duplicate charge, payout, discount, refund, or ledger entry
- Receipts come from the backend outcome
- Firestore emulator tests reject Rider and Driver tampering
- Unit, integration, concurrency, and failure tests pass
- Shadow differences are explained
- The complete flow is demonstrated in Stripe test mode
- Mentor approves formulas, security rules, and rollout plan

### Discord post 7 — First task

**Your first task: current-state audit**

Start with these files:

- `Features/Booking/RideManager.swift`
- `Features/Booking/FirestoreRideService.swift`
- `RydrDriver/RydrDriver/Features/Dashboard/DriverDashboardVM.swift`
- `stripe-backend/index.js`
- `Rydr_Firebase/firestore.rules`

Complete one emulator/test-mode ride. List every financial field, where it is calculated, who can write it, and where Stripe later reads it.

Your first deliverable is a short data-flow diagram and ownership table. Do not change pricing behavior until the mentor approves that audit and the expected test fixtures.
