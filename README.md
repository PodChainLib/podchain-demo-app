# podchain-demo-app

Demo mobile app for the PODCHAIN flow.

## Demo Data Seeding

The app reads tasks from `podchain-demo-api`. Seed data is created by calling demo API URLs.

### Prerequisites

1. Start `podchain-demo-api` (default: `http://127.0.0.1:3000`).
2. Login once in this app as a rider to register that rider key with the API.

If you skip step 2, seeding will fail with:

```json
{
  "success": false,
  "error": "RIDER_NOT_REGISTERED",
  "message": "Rider key is not registered yet. Login once in the demo app as this rider (or call POST /riders/register) before seeding tasks."
}
```

### Useful Seeding URLs

- Seed one task per tier and clear old pending demo tasks first:
  - `http://127.0.0.1:3000/demo/seed?riderId=rider_aisha_004&tiers=1,2,3&count=1&reset=true`
- Seed two OTP tasks:
  - `http://127.0.0.1:3000/demo/seed?riderId=rider_aisha_004&tiers=2&count=2`
- Seed two Tier-3 tasks:
  - `http://127.0.0.1:3000/demo/seed?riderId=rider_aisha_004&tiers=3&count=2`

### Check Registered Riders

- `http://127.0.0.1:3000/demo/riders`

Response shape:

```json
{
  "success": true,
  "registeredRiders": ["rider_aisha_004", "rider_emeka_001"]
}
```

### Bootstrap Endpoint (When No Riders Exist)

If `/demo/riders` returns an empty list, create a rider and seed tasks in one request:

- `POST http://127.0.0.1:3000/demo/bootstrap`

Body:

```json
{
  "riderId": "rider_aisha_004",
  "publicKey": { "kty": "EC", "crv": "P-256", "x": "...", "y": "..." },
  "tiers": [1, 2, 3],
  "count": 1,
  "reset": true
}
```

After bootstrap succeeds, tap **Refresh riders** on the login screen and continue.

### Notes

- `tiers` supports any combination of `1,2,3`.
- `count` is per tier requested.
- `reset=true` deletes only pending, uncompleted tasks for that rider before seeding.
