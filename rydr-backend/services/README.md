# Backend services

These packages are independently deployed even though their source is grouped
under the main backend folder.

| Service | Render root directory | Purpose |
| --- | --- | --- |
| Stripe | `rydr-backend/services/stripe` | Payments, Connect, payouts, and billing |
| Rydr Bank | `rydr-backend/services/bank` | Rewards, promotions, and Rydr Bank policy |

Changing either directory requires updating the matching Render service, not
the primary `rydr-backend` service. Each package has its own lockfile and must
pass `npm test` independently.
