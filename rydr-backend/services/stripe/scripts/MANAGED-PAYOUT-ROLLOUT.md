# Live Beta managed payouts

`STRIPE_CONNECT_MANAGED_SETUP_LIVE=true` enables managed account creation for new Live Beta drivers. Test uses independent keys and Firebase project. Existing IDs are never silently replaced.

For an **unused, incomplete Express account only**, run from the Stripe service root:

```
node scripts/migrate-unused-live-connect.js DRIVER_UID OLD_ACCOUNT_ID
```

This is read-only. It checks ownership, offline state, all-currency balances, Stripe transactions/charges/transfers/payouts, and Rydr rides/payout jobs. Any history requires a separately reconciled migration. A valid bank account already attached to Express does not transfer automatically.

After reviewing the dry-run, the human operator must run the final account-opening step:

```
MIGRATION_OPERATOR=YOUR_NAME node scripts/migrate-unused-live-connect.js DRIVER_UID OLD_ACCOUNT_ID --apply
```

The tool creates one idempotent candidate, records it before changing the profile, rechecks the old account, and atomically records the switch. It retains the old Stripe account and an audit under `stripeConnectMigrations`. No money moves; accepted terms and bank/card details are never copied. The driver must complete the embedded setup, enter their own bank/card, and accept required agreements. Payouts remain disabled until Stripe confirms readiness.

If creation succeeds but switching is blocked, the audit keeps the candidate for recovery. Do not delete the audit or old account. Existing completed accounts or any account with financial history are intentionally unsupported by this tool.

Release validation: Test actual bank and debit card setup passed with Stripe iOS 26.14.0; existing Test credentials are rejected from Live endpoints. Driver 27 includes the tested UI fixes. A real Live driver must still complete onboarding and a controlled payout before broader rollout.
